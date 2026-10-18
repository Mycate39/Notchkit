import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

/// Volume d'une app (macOS 14.2+, API publiques Core Audio) : le son de ses processus est intercepté
/// et coupé à la source, puis rejoué sur la sortie actuelle avec le gain choisi.
/// Demande l'autorisation « Enregistrement audio du système », comme les barres de l'égaliseur.
@available(macOS 14.2, *)
final class AppVolumeTap: @unchecked Sendable {
    /// Gain lu par le fil audio (écriture d'un Float : atomique en pratique sur Apple Silicon et Intel).
    private final class Gain: @unchecked Sendable {
        var value: Float
        init(_ value: Float) { self.value = value }
    }

    private let gain: Gain
    private let queue = DispatchQueue(label: "com.andeolchenaux.notchkit.appvolume", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    var volume: Float {
        get { gain.value }
        set { gain.value = min(1, max(0, newValue)) }
    }

    init(volume: Float) {
        gain = Gain(min(1, max(0, volume)))
    }

    deinit {
        stop()
    }

    /// Intercepte les processus donnés et les rejoue sur la sortie `outputUID`.
    func start(processes: [AudioObjectID], outputUID: String) throws {
        stop()
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        description.name = "Notchkit – volume par app"
        try check("création du tap", AudioHardwareCreateProcessTap(description, &tapID))

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Notchkit – volume par app",
            kAudioAggregateDeviceUIDKey: "com.andeolchenaux.notchkit.appvolume.\(UUID().uuidString)",
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

        let gain = gain
        try check("lecture", AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { _, input, _, output, _ in
            Self.copy(input, to: output, gain: gain.value)
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

    /// Recopie le son intercepté (Float32) vers la sortie en appliquant le gain ; le reste est mis à zéro.
    private static func copy(_ input: UnsafePointer<AudioBufferList>, to output: UnsafeMutablePointer<AudioBufferList>, gain: Float) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        var factor = gain
        for index in 0..<outputs.count {
            let out = outputs[index]
            guard let outData = out.mData else { continue }
            let outCount = Int(out.mDataByteSize) / MemoryLayout<Float>.size
            let destination = outData.assumingMemoryBound(to: Float.self)
            var copied = 0
            if inputs.count > 0 {
                let source = inputs[min(index, inputs.count - 1)]
                if let inData = source.mData {
                    copied = min(outCount, Int(source.mDataByteSize) / MemoryLayout<Float>.size)
                    vDSP_vsmul(inData.assumingMemoryBound(to: Float.self), 1, &factor, destination, 1, vDSP_Length(copied))
                }
            }
            if copied < outCount {
                (destination + copied).update(repeating: 0, count: outCount - copied)
            }
        }
    }

    private func check(_ step: String, _ status: OSStatus) throws {
        guard status == noErr else {
            stop()
            throw NSError(domain: "Notchkit.AppVolume", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Core Audio (\(step)) : erreur \(status)"])
        }
    }
}
