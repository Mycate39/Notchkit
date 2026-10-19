import AVFoundation
import Foundation

/// Petits sons de la mascotte, synthétisés à la volée (aucun fichier audio) : bips, carillons, grognements.
@MainActor
final class MascotSounds {
    enum Effect: CaseIterable, Sendable {
        /// Clic sur la mascotte.
        case tap
        /// Un agent se met au travail.
        case start
        /// Un agent attend une réponse.
        case question
        /// Tâche terminée, réponse reçue.
        case happy
        /// Erreur ou échec.
        case grumble
        /// Message envoyé dans la discussion.
        case send
        /// Syllabe pendant que la mascotte « parle ».
        case blip
        /// Nouvel événement (paiement, déploiement prêt).
        case coin
    }

    static let shared = MascotSounds()

    /// Réglages poussés par l'app (Apparence > Mascotte).
    static var isEnabled = true
    static var volume: Float = 0.5

    /// Hauteur globale des sons : les partitions sont transposées d'une quarte vers le grave.
    nonisolated static let pitch = 0.75

    /// Écart minimal entre deux syllabes, pour un babillage lisible et pas une rafale.
    static let blipInterval: TimeInterval = 0.09

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Effect: [AVAudioPCMBuffer]] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var stopTask: Task<Void, Never>?
    private var lastBlip = Date.distantPast
    private var isConfigured = false

    private init() {}

    /// Joue un effet (sans effet si les sons sont coupés ou pendant une exécution automatisée).
    func play(_ effect: Effect) {
        guard Self.isEnabled, Self.volume > 0, !AutomatedRun.isActive else { return }
        if effect == .blip {
            guard Date().timeIntervalSince(lastBlip) >= Self.blipInterval else { return }
            lastBlip = Date()
        }
        configureIfNeeded()
        guard let variants = buffers[effect], let buffer = variants.randomElement() else { return }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            return
        }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = Self.volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
        scheduleStop()
    }

    /// Moteur coupé après un moment de silence : aucune charge quand la mascotte se tait.
    private func scheduleStop() {
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self else { return }
            self.players.forEach { $0.stop() }
            self.engine.stop()
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        for _ in 0..<4 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        for effect in Effect.allCases {
            buffers[effect] = Self.variants(of: effect).compactMap(makeBuffer)
        }
    }

    private func makeBuffer(_ notes: [Note]) -> AVAudioPCMBuffer? {
        let samples = Self.render(notes, sampleRate: format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    // MARK: Synthèse (fonctions pures, testées)

    /// Note : glissement de fréquence, durée, départ (secondes) et intensité.
    struct Note: Equatable, Sendable {
        var from: Double
        var to: Double
        var duration: Double
        var start: Double = 0
        var gain: Double = 1
        /// Part de son « carré » (plus rétro) mêlée à la sinusoïde, de 0 à 1.
        var grit: Double = 0.15
    }

    /// Partitions de chaque effet ; plusieurs variantes pour ne pas toujours entendre la même chose.
    nonisolated static func variants(of effect: Effect) -> [[Note]] {
        switch effect {
        case .tap:
            [[Note(from: 620, to: 880, duration: 0.07), Note(from: 880, to: 1180, duration: 0.09, start: 0.06)],
             [Note(from: 900, to: 700, duration: 0.06), Note(from: 1050, to: 1320, duration: 0.1, start: 0.05)],
             [Note(from: 520, to: 1040, duration: 0.14, gain: 0.9)]]
        case .start:
            [[Note(from: 440, to: 520, duration: 0.07, gain: 0.7), Note(from: 660, to: 700, duration: 0.08, start: 0.07, gain: 0.7)]]
        case .question:
            [[Note(from: 700, to: 700, duration: 0.09), Note(from: 760, to: 1180, duration: 0.17, start: 0.1)]]
        case .happy:
            [[Note(from: 784, to: 784, duration: 0.08), Note(from: 988, to: 988, duration: 0.08, start: 0.08),
              Note(from: 1175, to: 1175, duration: 0.08, start: 0.16), Note(from: 1568, to: 1568, duration: 0.2, start: 0.24)]]
        case .grumble:
            [[Note(from: 220, to: 160, duration: 0.16, grit: 0.5), Note(from: 190, to: 120, duration: 0.2, start: 0.14, grit: 0.5)]]
        case .send:
            [[Note(from: 500, to: 1300, duration: 0.09, gain: 0.7, grit: 0)]]
        case .blip:
            [500.0, 560, 620, 680, 740].map { [Note(from: $0, to: $0 * 1.08, duration: 0.045, gain: 0.45, grit: 0.35)] }
        case .coin:
            [[Note(from: 988, to: 988, duration: 0.07, grit: 0.3), Note(from: 1319, to: 1319, duration: 0.28, start: 0.07, grit: 0.3)]]
        }
    }

    /// Échantillons d'une partition : sinusoïde (mêlée de carré), attaque brève et extinction douce.
    nonisolated static func render(_ notes: [Note], sampleRate: Double) -> [Float] {
        let length = notes.map { $0.start + $0.duration }.max() ?? 0
        var samples = [Float](repeating: 0, count: Int(length * sampleRate) + 1)
        for note in notes {
            let first = Int(note.start * sampleRate)
            let count = Int(note.duration * sampleRate)
            var phase = 0.0
            for index in 0..<count where first + index < samples.count {
                let progress = Double(index) / Double(max(1, count))
                let frequency = (note.from + (note.to - note.from) * progress) * pitch
                phase += 2 * .pi * frequency / sampleRate
                let sine = sin(phase)
                let square: Double = sine >= 0 ? 1 : -1
                let tone = sine * (1 - note.grit) + square * note.grit * 0.5
                let attack = min(1, progress / 0.08)
                let release = pow(1 - progress, 1.6)
                samples[first + index] += Float(tone * attack * release * note.gain * 0.35)
            }
        }
        return samples.map { min(1, max(-1, $0)) }
    }
}
