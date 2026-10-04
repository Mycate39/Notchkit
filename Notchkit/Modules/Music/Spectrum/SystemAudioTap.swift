import CoreAudio
import Foundation

/// Capture du son de sortie du Mac (API publique Core Audio « process taps », macOS 14.2+).
///
/// On crée un « tap » global (tout le son du système, mixé en mono, sans le couper), puis
/// un périphérique agrégé privé qui le lit. Le son reçu n'est jamais enregistré ni envoyé :
/// il sert uniquement à animer les barres. macOS demande l'autorisation « Enregistrement
/// audio du système » et affiche un indicateur tant que la capture tourne.
///
/// Toutes les opérations se font sur `queue` (série) ; la classe n'est pas utilisée ailleurs.
@available(macOS 14.2, *)
final class SystemAudioTap: @unchecked Sendable {
    enum TapError: LocalizedError {
        case coreAudio(String, OSStatus)
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case let .coreAudio(step, status): "Core Audio (\(step)) : erreur \(status)"
            case .unsupportedFormat: "Format audio non pris en charge"
            }
        }
    }

    /// Reçoit des échantillons mono (Float32) et la fréquence d'échantillonnage.
    typealias SampleHandler = (UnsafeBufferPointer<Float>, Float) -> Void

    private let queue: DispatchQueue
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var monoBuffer: [Float] = []

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    deinit {
        stop()
    }

    func start(handler: @escaping SampleHandler) throws {
        stop()

        // 1. Tap global mono, qui ne coupe pas le son.
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        description.name = "Notchkit"
        try check("création du tap", AudioHardwareCreateProcessTap(description, &tapID))

        // 2. Format du tap.
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        try check("format du tap", AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format))
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0 else {
            stop()
            throw TapError.unsupportedFormat
        }

        // 3. Périphérique agrégé privé contenant uniquement le tap.
        let outputUID = try Self.defaultOutputDeviceUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Notchkit – analyse audio",
            kAudioAggregateDeviceUIDKey: "com.andeolchenaux.notchkit.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        try check("périphérique agrégé", AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID))

        // 4. Lecture des échantillons.
        let sampleRate = Float(format.mSampleRate)
        let channels = Int(max(1, format.mChannelsPerFrame))
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        try check("lecture", AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.consume(input, channels: channels, interleaved: interleaved, sampleRate: sampleRate, handler: handler)
        })
        try check("démarrage", AudioDeviceStart(aggregateID, ioProcID))
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    // MARK: - Privé

    /// Convertit le tampon reçu en échantillons mono.
    private func consume(_ input: UnsafePointer<AudioBufferList>, channels: Int, interleaved: Bool,
                         sampleRate: Float, handler: SampleHandler) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let data = first.mData else { return }

        if interleaved {
            let total = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.assumingMemoryBound(to: Float.self)
            if channels == 1 {
                handler(UnsafeBufferPointer(start: samples, count: total), sampleRate)
                return
            }
            let frames = total / channels
            if monoBuffer.count < frames { monoBuffer = [Float](repeating: 0, count: frames) }
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels { sum += samples[frame * channels + channel] }
                monoBuffer[frame] = sum / Float(channels)
            }
            monoBuffer.withUnsafeBufferPointer { handler(UnsafeBufferPointer(rebasing: $0[0..<frames]), sampleRate) }
        } else {
            // Non entrelacé : on prend le premier canal (le tap est déjà mixé en mono).
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            handler(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: frames), sampleRate)
        }
    }

    private func check(_ step: String, _ status: OSStatus) throws {
        guard status == noErr else {
            stop()
            throw TapError.coreAudio(step, status)
        }
    }

    private static func defaultOutputDeviceUID() throws -> String {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr else { throw TapError.coreAudio("sortie audio", status) }

        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { throw TapError.coreAudio("identifiant de sortie", status) }
        return uid.takeRetainedValue() as String
    }
}
