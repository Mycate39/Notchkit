import Accelerate
import AppKit
import CoreAudio
import Observation

/// Fournit en temps réel les niveaux des bandes de fréquences du son joué par le Mac.
///
/// Les niveaux (≈ 60 par seconde) sont envoyés directement aux abonnés (les barres de
/// l'égaliseur, en Core Animation) sans passer par SwiftUI, pour rester économe.
/// `nil` signifie « pas de données en direct » : les barres reprennent leur animation simple.
@MainActor
@Observable
final class AudioSpectrumMonitor {
    enum Status: Equatable {
        case stopped
        case running
        /// La capture tourne mais ne reçoit que du silence depuis plusieurs secondes
        /// (souvent : autorisation refusée).
        case silent
        case unsupported
        case failed(String)
    }

    private(set) var status: Status = .stopped

    @ObservationIgnored private var subscribers: [UUID: @MainActor ([Float]?) -> Void] = [:]
    @ObservationIgnored private let queue = DispatchQueue(label: "com.andeolchenaux.notchkit.spectrum", qos: .userInteractive)
    @ObservationIgnored private var tap: AnyObject?
    @ObservationIgnored private var processor: SpectrumProcessor?

    // MARK: Abonnements

    func subscribe(_ handler: @escaping @MainActor ([Float]?) -> Void) -> UUID {
        let id = UUID()
        subscribers[id] = handler
        return id
    }

    func unsubscribe(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    private func publish(_ levels: [Float]?) {
        subscribers.values.forEach { $0(levels) }
    }

    // MARK: Capture

    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        guard #available(macOS 14.2, *) else {
            status = .unsupported
            return
        }

        let processor = SpectrumProcessor { [weak self] levels in
            // Appelé sur la file audio : on repasse sur le thread principal.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(levels) }
            }
        }
        let tap = SystemAudioTap(queue: queue)
        let queue = queue
        do {
            // Démarrage sur la file audio : c'est elle qui recevra les échantillons.
            try queue.sync {
                try tap.start { samples, sampleRate in
                    processor.ingest(samples, sampleRate: sampleRate)
                }
            }
            self.tap = tap
            self.processor = processor
            status = .running
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func stop() {
        guard let tap else { return }
        if #available(macOS 14.2, *), let tap = tap as? SystemAudioTap {
            queue.sync { tap.stop() }
        }
        self.tap = nil
        processor = nil
        status = .stopped
        publish(nil)
    }

    private func receive(_ levels: [Float]?) {
        guard tap != nil else { return }
        if let levels {
            if status != .running { status = .running }
            publish(levels)
        } else {
            if status != .silent { status = .silent }
            publish(nil)
        }
    }
}

/// Accumule les échantillons, lance l'analyse et limite la fréquence des mises à jour.
/// Utilisé uniquement sur la file audio.
private final class SpectrumProcessor: @unchecked Sendable {
    private let analyzer = SpectrumAnalyzer(fftSize: 1024)
    private var smoother = SpectrumSmoother(bandCount: SpectrumAnalyzer.defaultBandCount)
    private var buffer: [Float] = []
    private var lastPublish: CFAbsoluteTime = 0
    private var silentSince: CFAbsoluteTime?
    private let onLevels: ([Float]?) -> Void

    /// 60 mises à jour par seconde pour des barres très réactives.
    private static let publishInterval: CFAbsoluteTime = 1.0 / 60
    /// Au-delà de ce délai de silence total, on considère qu'il n'y a pas de son capté.
    private static let silenceTimeout: CFAbsoluteTime = 6

    init(onLevels: @escaping ([Float]?) -> Void) {
        self.onLevels = onLevels
    }

    func ingest(_ samples: UnsafeBufferPointer<Float>, sampleRate: Float) {
        buffer.append(contentsOf: samples)
        // On garde seulement la dernière fenêtre d'analyse.
        if buffer.count > analyzer.fftSize { buffer.removeFirst(buffer.count - analyzer.fftSize) }

        let now = CFAbsoluteTimeGetCurrent()
        guard buffer.count == analyzer.fftSize, now - lastPublish >= Self.publishInterval else { return }
        lastPublish = now

        // Silence total (son coupé, ou autorisation refusée : le tap ne reçoit que des zéros).
        var peak: Float = 0
        vDSP_maxmgv(buffer, 1, &peak, vDSP_Length(buffer.count))
        if peak < 1e-6 {
            if silentSince == nil { silentSince = now }
            if let since = silentSince, now - since > Self.silenceTimeout {
                onLevels(nil)
                return
            }
        } else {
            silentSince = nil
        }

        let energies = analyzer.bandEnergies(buffer, sampleRate: sampleRate)
        onLevels(smoother.update(with: energies))
    }
}
