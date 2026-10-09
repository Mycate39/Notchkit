import AppKit
import AudioToolbox
import CoreAudio

/// Volume de la sortie audio par défaut (API publique Core Audio).
enum SystemVolume {
    static func defaultOutputDevice() -> AudioObjectID? {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != kAudioObjectUnknown ? id : nil
    }

    static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Vrai si la sortie actuelle a un volume réglable (faux pour beaucoup d'écrans HDMI/DisplayPort).
    static var isAdjustable: Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = volumeAddress()
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address)
            && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    static var volume: Float {
        get {
            guard let device = defaultOutputDevice() else { return 0 }
            var address = volumeAddress()
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : 0
        }
        set {
            guard let device = defaultOutputDevice() else { return }
            var address = volumeAddress()
            var value = Float32(min(1, max(0, newValue)))
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
    }

    static var isMuted: Bool {
        get {
            guard let device = defaultOutputDevice() else { return false }
            var address = muteAddress()
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
        }
        set {
            guard let device = defaultOutputDevice() else { return }
            var address = muteAddress()
            var value: UInt32 = newValue ? 1 : 0
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }
}

/// Prévient à chaque changement de volume ou de sourdine de la sortie par défaut, quelle qu'en
/// soit la source : Touch Bar, Centre de contrôle, autre app. Les touches du clavier ne suffisent
/// pas, car la Touch Bar règle le volume directement, sans envoyer de touche.
@MainActor
final class VolumeObserver {
    var onChange: (@MainActor () -> Void)?

    private var device: AudioObjectID?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var defaultListener: AudioObjectPropertyListenerBlock?

    private static let defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard defaultListener == nil else { return }
        // Changement de sortie (casque branché…) : on suit la nouvelle sortie par défaut.
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachToDefaultOutput() }
        }
        var address = Self.defaultOutputAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        defaultListener = listener
        attachToDefaultOutput()
    }

    func stop() {
        detach()
        if let listener = defaultListener {
            var address = Self.defaultOutputAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        defaultListener = nil
    }

    private func attachToDefaultOutput() {
        detach()
        guard let id = SystemVolume.defaultOutputDevice() else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        for var address in [SystemVolume.volumeAddress(), SystemVolume.muteAddress()] {
            AudioObjectAddPropertyListenerBlock(id, &address, .main, listener)
        }
        device = id
        deviceListener = listener
    }

    private func detach() {
        guard let device, let listener = deviceListener else { return }
        for var address in [SystemVolume.volumeAddress(), SystemVolume.muteAddress()] {
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, listener)
        }
        self.device = nil
        deviceListener = nil
    }
}

/// Luminosité de l'écran intégré.
///
/// ⚠️ API PRIVÉE : framework DisplayServices, chargé dynamiquement. S'il est absent ou modifié
/// par une mise à jour de macOS, `isAvailable` devient faux et Notchkit laisse les touches
/// de luminosité à macOS (aucun plantage).
enum DisplayBrightness {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private struct Functions: @unchecked Sendable {
        let get: GetBrightness
        let set: SetBrightness
    }

    private static let functions: Functions? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness")
        else { return nil }
        return Functions(get: unsafeBitCast(get, to: GetBrightness.self), set: unsafeBitCast(set, to: SetBrightness.self))
    }()

    /// Écran intégré (MacBook), s'il est allumé.
    static var builtInDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &displays, &count)
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var isAvailable: Bool {
        guard functions != nil, let display = builtInDisplay else { return false }
        var value: Float = 0
        return functions?.get(display, &value) == 0
    }

    static var brightness: Float? {
        get {
            guard let functions, let display = builtInDisplay else { return nil }
            var value: Float = 0
            return functions.get(display, &value) == 0 ? value : nil
        }
        set {
            guard let functions, let display = builtInDisplay, let newValue else { return }
            _ = functions.set(display, min(1, max(0, newValue)))
        }
    }
}
