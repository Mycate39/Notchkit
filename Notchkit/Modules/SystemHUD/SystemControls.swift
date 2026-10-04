import AppKit
import AudioToolbox
import CoreAudio

/// Volume de la sortie audio par défaut (API publique Core Audio).
enum SystemVolume {
    private static func defaultOutputDevice() -> AudioObjectID? {
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

    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
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
