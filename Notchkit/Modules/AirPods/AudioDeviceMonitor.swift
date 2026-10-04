import CoreAudio
import Foundation

/// Casque ou écouteurs Bluetooth vus comme sortie audio par macOS.
struct HeadphoneDevice: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case airPods
        case airPodsPro
        case airPodsMax
        case beats
        case other

        /// Modèle déduit du nom de l'appareil (« AirPods Pro de Léa »…).
        init(name: String) {
            let lower = name.lowercased()
            if lower.contains("airpods max") { self = .airPodsMax }
            else if lower.contains("airpods pro") { self = .airPodsPro }
            else if lower.contains("airpods") { self = .airPods }
            else if lower.contains("beats") || lower.contains("powerbeats") { self = .beats }
            else { self = .other }
        }

        var symbol: String {
            switch self {
            case .airPods: "airpods.gen3"
            case .airPodsPro: "airpods.pro"
            case .airPodsMax: "airpodsmax"
            case .beats: "beats.headphones"
            case .other: "headphones"
            }
        }
    }

    let id: AudioObjectID
    let uid: String
    let name: String
    var isDefaultOutput: Bool

    var kind: Kind { Kind(name: name) }
}

/// Événements de connexion déduits de deux listes successives.
enum HeadphoneEvent: Equatable, Sendable {
    case connected(HeadphoneDevice)
    case disconnected(HeadphoneDevice)

    static func events(from old: [HeadphoneDevice], to new: [HeadphoneDevice]) -> [HeadphoneEvent] {
        let oldUIDs = Set(old.map(\.uid))
        let newUIDs = Set(new.map(\.uid))
        return new.filter { !oldUIDs.contains($0.uid) }.map(HeadphoneEvent.connected)
            + old.filter { !newUIDs.contains($0.uid) }.map(HeadphoneEvent.disconnected)
    }
}

/// Suit les sorties audio Bluetooth (API publique Core Audio, aucune autorisation nécessaire).
/// macOS prévient à chaque changement de la liste des périphériques ou de la sortie par défaut.
@MainActor
final class AudioDeviceMonitor {
    var onChange: (@MainActor ([HeadphoneDevice]) -> Void)?
    private(set) var devices: [HeadphoneDevice] = []

    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func start() {
        guard listeners.isEmpty else { return }
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = Self.address(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                // Bloc appelé sur la file principale (voir ci-dessous).
                MainActor.assumeIsolated { self?.refresh() }
            }
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
            listeners.append((address, block))
        }
        refresh()
    }

    func stop() {
        for (address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
        listeners.removeAll()
    }

    /// Fait de l'appareil la sortie audio par défaut.
    func makeDefaultOutput(_ device: HeadphoneDevice) {
        var id = device.id
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                   UInt32(MemoryLayout<AudioObjectID>.size), &id)
    }

    private func refresh() {
        let current = Self.currentHeadphones()
        guard current != devices else { return }
        devices = current
        onChange?(current)
    }

    // MARK: - Lecture Core Audio

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func currentHeadphones() -> [HeadphoneDevice] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        var defaultID = AudioObjectID(kAudioObjectUnknown)
        var defaultSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var defaultAddress = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(system, &defaultAddress, 0, nil, &defaultSize, &defaultID)

        return ids.compactMap { id in
            let transport = uint32(id, kAudioDevicePropertyTransportType)
            guard transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
                  hasOutput(id),
                  let name = string(id, kAudioObjectPropertyName),
                  let uid = string(id, kAudioDevicePropertyDeviceUID)
            else { return nil }
            return HeadphoneDevice(id: id, uid: uid, name: name, isDefaultOutput: id == defaultID)
        }
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = address(selector)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = address(selector)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func hasOutput(_ id: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }
}
