import AppKit
import AudioToolbox
import CoreAudio
import Observation

/// Appareil audio (sortie ou entrée).
struct AudioDevice: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case builtIn, bluetooth, usb, display, airPlay, virtual, other }

    let id: AudioObjectID
    let name: String
    let kind: Kind
    let hasOutput: Bool
    let hasInput: Bool

    /// Symbole selon le nom et le type de connexion.
    var symbol: String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        switch kind {
        case .builtIn: return hasOutput ? "laptopcomputer" : "mic.fill"
        case .bluetooth: return lower.contains("beats") || lower.contains("casque") || lower.contains("headphone") ? "headphones" : "hifispeaker.fill"
        case .usb: return hasOutput ? "headphones" : "mic.fill"
        case .display: return "display"
        case .airPlay: return "airplayaudio"
        case .virtual: return "waveform"
        case .other: return "speaker.wave.2.fill"
        }
    }

    static func kind(transport: UInt32) -> Kind {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        case kAudioDeviceTransportTypeUSB: .usb
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: .display
        case kAudioDeviceTransportTypeAirPlay: .airPlay
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: .virtual
        default: .other
        }
    }
}

/// App qui émet du son en ce moment.
struct AudioApp: Identifiable, Equatable {
    let id: pid_t
    let name: String
    let bundleID: String?
    /// Objets audio Core Audio de l'app et de ses processus auxiliaires (navigateurs…).
    let processObjects: [AudioObjectID]
    let icon: NSImage?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.processObjects == rhs.processObjects
    }
}

/// Centre du son : appareils d'entrée et de sortie, volume de chacun, apps qui jouent.
/// API publiques Core Audio uniquement ; la liste des apps demande macOS 14.2.
@MainActor
@Observable
final class AudioCenter {
    private(set) var outputs: [AudioDevice] = []
    private(set) var inputs: [AudioDevice] = []
    private(set) var defaultOutput: AudioObjectID?
    private(set) var defaultInput: AudioObjectID?
    private(set) var playingApps: [AudioApp] = []
    /// Volume choisi par app (identifiant de processus) ; absent = 100 %.
    private(set) var appVolumes: [pid_t: Float] = [:]
    private(set) var appVolumeError: String?

    /// Interceptions en cours (une par app dont le volume n'est pas à 100 %).
    @ObservationIgnored private var appTaps: [pid_t: AnyObject] = [:]
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var appsTask: Task<Void, Never>?
    /// Identifiant de l'app en cours de lecture selon le module Musique (`nil` en pause ou sans musique).
    @ObservationIgnored var nowPlayingBundleID: (() -> String?)?

    func start() {
        isVisible = true
        startAppsPolling()
        guard listeners.isEmpty else { return }
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice,
                         kAudioHardwarePropertyDefaultInputDevice] {
            var address = Self.address(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshDevices() } }
            }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
                listeners.append((address, block))
            }
        }
        refreshDevices()
    }

    /// Les apps qui jouent changent souvent : relevé toutes les deux secondes tant que le centre est affiché.
    private func startAppsPolling() {
        guard appsTask == nil else { return }
        appsTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshApps()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        isVisible = false
        appsTask?.cancel()
        appsTask = nil
        // Des volumes par app sont en place : on garde l'écoute de la sortie pour les suivre.
        guard appTaps.isEmpty else { return }
        for (address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
        listeners.removeAll()
    }

    // MARK: Appareils

    func refreshDevices() {
        let devices = Self.allDeviceIDs().compactMap(Self.device(for:))
        outputs = devices.filter { $0.hasOutput && $0.kind != .virtual }
        inputs = devices.filter { $0.hasInput && $0.kind != .virtual }
        let previousOutput = defaultOutput
        defaultOutput = Self.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        defaultInput = Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        // Nouvelle sortie : les volumes par app sont rejoués dessus.
        if previousOutput != nil, previousOutput != defaultOutput { rebuildAppTaps() }
    }

    // MARK: Volume par app

    /// Règle le volume d'une app ; à 100 %, l'interception est retirée et l'app sonne normalement.
    func setVolume(_ volume: Float, for app: AudioApp) {
        guard #available(macOS 14.2, *) else { return }
        let volume = min(1, max(0, volume))
        if volume >= 0.995 {
            (appTaps.removeValue(forKey: app.id) as? AppVolumeTap)?.stop()
            appVolumes[app.id] = nil
            if !isVisible && appTaps.isEmpty { stop() }
            return
        }
        appVolumes[app.id] = volume
        if let tap = appTaps[app.id] as? AppVolumeTap {
            tap.volume = volume
            return
        }
        startTap(for: app.id, processes: app.processObjects, volume: volume)
    }

    private func startTap(for pid: pid_t, processes: [AudioObjectID], volume: Float) {
        guard #available(macOS 14.2, *) else { return }
        guard let output = defaultOutput, let uid = Self.string(output, kAudioDevicePropertyDeviceUID) else { return }
        let tap = AppVolumeTap(volume: volume)
        do {
            try tap.start(processes: processes, outputUID: uid)
            appTaps[pid] = tap
            appVolumeError = nil
            // Écoute de la sortie (pour suivre un changement d'appareil), même carte fermée.
            if listeners.isEmpty {
                let wasVisible = isVisible
                start()
                if !wasVisible { stop() }
            }
        } catch {
            appVolumes[pid] = nil
            appVolumeError = error.localizedDescription
        }
    }

    private func rebuildAppTaps() {
        guard #available(macOS 14.2, *) else { return }
        for (pid, object) in appTaps {
            (object as? AppVolumeTap)?.stop()
            appTaps[pid] = nil
            if let volume = appVolumes[pid], let app = playingApps.first(where: { $0.id == pid }) {
                startTap(for: pid, processes: app.processObjects, volume: volume)
            } else {
                appVolumes[pid] = nil
            }
        }
    }

    func makeDefault(_ device: AudioDevice, input: Bool) {
        var id = device.id
        var address = Self.address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                   UInt32(MemoryLayout<AudioObjectID>.size), &id)
        if input { defaultInput = device.id } else { defaultOutput = device.id }
    }

    /// Volume d'un appareil (0…1), `nil` s'il n'est pas réglable.
    func volume(of device: AudioObjectID, input: Bool) -> Float? {
        var address = Self.volumeAddress(input: input)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    func setVolume(_ volume: Float, of device: AudioObjectID, input: Bool) {
        var address = Self.volumeAddress(input: input)
        var value = Float32(min(1, max(0, volume)))
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    // MARK: Apps qui jouent

    func refreshApps() {
        guard #available(macOS 14.2, *) else { return }
        var owners: [pid_t: NSRunningApplication] = [:]
        var entries: [(object: AudioObjectID, owner: pid_t, output: Bool)] = []
        for object in Self.processObjects() {
            guard let pid = Self.pid(of: object), let app = Self.owningApp(of: pid) else { continue }
            owners[app.processIdentifier] = app
            entries.append((object, app.processIdentifier, Self.bool(object, kAudioProcessPropertyIsRunningOutput)))
        }
        // Les navigateurs ne signalent pas toujours leur sortie : l'app « À l'écoute » est ajoutée d'office.
        let nowPlaying = nowPlayingBundleID?().flatMap { id in owners.values.first { $0.bundleIdentifier == id } }
        let groups = Self.playingGroups(entries, nowPlaying: nowPlaying?.processIdentifier)
        let apps = groups.compactMap { pid, objects -> AudioApp? in
            guard let app = owners[pid] else { return nil }
            return AudioApp(id: pid, name: app.localizedName ?? "App", bundleID: app.bundleIdentifier,
                            processObjects: objects, icon: app.icon)
        }
            .filter { $0.bundleID != Bundle.main.bundleIdentifier }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if apps != playingApps { playingApps = apps }
    }

    /// Apps qui jouent, avec tous leurs objets audio (app et processus auxiliaires) : une app est retenue
    /// si l'un de ses processus émet du son, ou si c'est l'app « À l'écoute ».
    nonisolated static func playingGroups(_ entries: [(object: AudioObjectID, owner: pid_t, output: Bool)],
                                          nowPlaying: pid_t?) -> [pid_t: [AudioObjectID]] {
        var playing = Set(entries.filter(\.output).map(\.owner))
        if let nowPlaying { playing.insert(nowPlaying) }
        var groups: [pid_t: [AudioObjectID]] = [:]
        for entry in entries where playing.contains(entry.owner) {
            groups[entry.owner, default: []].append(entry.object)
        }
        return groups.mapValues { $0.sorted() }
    }

    /// App « principale » d'un processus : un processus auxiliaire (ex. « Google Chrome Helper »)
    /// est rattaché à l'app qui le contient.
    static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        guard let process = NSRunningApplication(processIdentifier: pid) else { return nil }
        if process.activationPolicy == .regular { return process }
        guard let url = process.bundleURL, let outer = outermostApp(in: url.path) else { return process }
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == outer } ?? process
    }

    /// Chemin de l'app la plus extérieure qui contient `path` (« …/Chrome.app/…/Helper.app » → « …/Chrome.app »).
    nonisolated static func outermostApp(in path: String) -> String? {
        guard let range = path.range(of: ".app") else { return nil }
        return String(path[..<range.upperBound])
    }

    // MARK: Core Audio

    nonisolated static func address(_ selector: AudioObjectPropertySelector,
                                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func volumeAddress(input: Bool) -> AudioObjectPropertyAddress {
        address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                scope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput)
    }

    private static func allDeviceIDs() -> [AudioObjectID] {
        objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
    }

    private static func processObjects() -> [AudioObjectID] {
        guard #available(macOS 14.2, *) else { return [] }
        return objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
    }

    private static func objectList(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = address(selector)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != kAudioObjectUnknown ? id : nil
    }

    private static func device(for id: AudioObjectID) -> AudioDevice? {
        guard let name = string(id, kAudioObjectPropertyName) else { return nil }
        let transport = uint32(id, kAudioDevicePropertyTransportType) ?? 0
        return AudioDevice(id: id, name: name, kind: AudioDevice.kind(transport: transport),
                           hasOutput: hasStreams(id, scope: kAudioDevicePropertyScopeOutput),
                           hasInput: hasStreams(id, scope: kAudioDevicePropertyScopeInput))
    }

    private static func hasStreams(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: scope)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = address(selector)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func bool(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        (uint32(id, selector) ?? 0) != 0
    }

    private static func pid(of process: AudioObjectID) -> pid_t? {
        guard #available(macOS 14.2, *) else { return nil }
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        var address = address(kAudioProcessPropertyPID)
        return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = address(selector)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
