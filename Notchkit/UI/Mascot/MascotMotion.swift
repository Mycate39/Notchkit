import Foundation
import SwiftUI

/// Posture de la mascotte à un instant donné.
struct MascotPose: Equatable {
    /// Décalage vertical, en fraction de la taille (négatif = vers le haut).
    var lift: CGFloat = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    /// Inclinaison en degrés.
    var tilt: Double = 0
    var blink: CGFloat = 0
    var gaze: CGSize = .zero
    /// Demi-tour sur elle-même (degrés autour de l'axe vertical).
    var turn: Double = 0
}

/// Réaction à un clic ; chaque clic passe à la suivante.
enum MascotReaction: Int, CaseIterable, Sendable {
    case jump, spin, squish, wiggle

    var duration: TimeInterval {
        switch self {
        case .jump: 0.7
        case .spin: 0.75
        case .squish: 0.65
        case .wiggle: 0.6
        }
    }

    var next: MascotReaction { MascotReaction(rawValue: (rawValue + 1) % Self.allCases.count) ?? .jump }
}

/// Attitude pendant une discussion avec la mascotte.
enum MascotChatPhase: Equatable, Sendable {
    /// L'utilisateur écrit : elle se penche vers le champ et hoche la tête.
    case listening
    /// Avant le premier mot de la réponse : regard en l'air, tête qui balance.
    case thinking
    /// La réponse s'affiche : petits rebonds au rythme des syllabes.
    case talking
}

/// Mouvements de la mascotte : une fonction pure du temps écoulé dans l'humeur courante,
/// pour des animations identiques dans l'app, les captures et les vidéos.
enum MascotMotion {
    /// Période de respiration au repos (secondes).
    static let breathPeriod = 3.2
    /// Intervalle entre deux clignements (secondes) et durée d'un clignement.
    static let blinkInterval = 3.7
    static let blinkDuration = 0.16

    /// Posture à l'instant `t` (secondes depuis le début de l'humeur).
    static func pose(at t: TimeInterval, mood: MascotMood) -> MascotPose {
        var pose = MascotPose()
        // Respiration : léger gonflement, en permanence.
        let breath = sin(2 * .pi * t / breathPeriod)
        pose.scaleY = 1 + 0.025 * breath
        pose.scaleX = 1 - 0.012 * breath
        pose.blink = blink(at: t)

        switch mood {
        case .idle:
            // Le regard se promène doucement.
            pose.gaze = CGSize(width: 0.8 * sin(t * 0.6), height: 0.3 * sin(t * 0.37))
        case .working:
            // Petits hochements rapides, regard qui balaie la ligne.
            pose.lift = -0.03 * abs(sin(2 * .pi * t / 0.6))
            pose.gaze = CGSize(width: sin(t * 2.2), height: 0.6)
        case .waiting:
            // Pulsation et petit saut toutes les deux secondes pour attirer l'attention.
            let pulse = 0.5 + 0.5 * sin(2 * .pi * t)
            pose.scaleX *= 1 + 0.04 * pulse
            pose.scaleY *= 1 + 0.04 * pulse
            pose.lift = -0.12 * hop(at: t, period: 2, duration: 0.45)
            pose.gaze = .zero
        case .happy:
            // Sauts de joie, avec écrasement à l'atterrissage.
            let period = 1.2
            let phase = t.truncatingRemainder(dividingBy: period)
            pose.lift = -0.2 * hop(at: t, period: period, duration: 0.6)
            if phase > 0.6 && phase < 0.78 {
                let squash = sin(.pi * (phase - 0.6) / 0.18)
                pose.scaleY *= 1 - 0.1 * squash
                pose.scaleX *= 1 + 0.1 * squash
            }
            pose.blink = 0
        case .angry:
            // Tremblements par salves, regard droit devant.
            let burst = t.truncatingRemainder(dividingBy: 1.5)
            if burst < 0.5 {
                pose.tilt = 7 * sin(2 * .pi * 12 * t) * (1 - burst / 0.5)
            }
            pose.gaze = .zero
        }
        return pose
    }

    /// Posture pendant une discussion (remplace les mouvements de l'humeur, garde respiration et clignements).
    static func pose(at t: TimeInterval, chat phase: MascotChatPhase) -> MascotPose {
        var pose = MascotPose()
        let breath = sin(2 * .pi * t / breathPeriod)
        pose.scaleY = 1 + 0.02 * breath
        pose.scaleX = 1 - 0.01 * breath
        pose.blink = blink(at: t)
        switch phase {
        case .listening:
            // Penchée vers la saisie, petit hochement toutes les 1,4 s.
            pose.tilt = -5 + 3 * hop(at: t, period: 1.4, duration: 0.35)
            pose.lift = -0.03 * hop(at: t, period: 1.4, duration: 0.35)
            pose.gaze = CGSize(width: 0.5, height: 0.9)
        case .thinking:
            // Regard en l'air qui hésite, tête qui balance lentement.
            pose.tilt = 6 * sin(2 * .pi * t / 2.4)
            pose.lift = -0.04 - 0.02 * sin(2 * .pi * t / 1.2)
            pose.gaze = CGSize(width: -0.6 + 0.4 * sin(t * 1.3), height: -0.9)
        case .talking:
            // Syllabes : rebonds rapides et irréguliers, avec léger écrasement.
            let beat = abs(sin(2 * .pi * t * 3.1)) * (0.6 + 0.4 * abs(sin(2 * .pi * t * 0.7)))
            pose.lift = -0.05 * beat
            pose.scaleY *= 1 + 0.05 * beat
            pose.scaleX *= 1 - 0.03 * beat
            pose.tilt = 2.5 * sin(2 * .pi * t * 0.9)
            pose.gaze = CGSize(width: 0.3 * sin(t * 1.7), height: 0.1)
        }
        return pose
    }

    /// Ajoute une réaction au clic à la posture, `t` secondes après le clic (sans effet une fois finie).
    static func apply(_ reaction: MascotReaction, at t: TimeInterval, to pose: inout MascotPose) {
        guard t >= 0, t < reaction.duration else { return }
        let progress = t / reaction.duration
        switch reaction {
        case .jump:
            // Saut haut, puis écrasement à l'atterrissage.
            if progress < 0.7 {
                pose.lift -= 0.38 * CGFloat(sin(.pi * progress / 0.7))
                pose.scaleY *= 1 + 0.08 * CGFloat(sin(.pi * progress / 0.7))
            } else {
                let squash = CGFloat(sin(.pi * (progress - 0.7) / 0.3))
                pose.scaleY *= 1 - 0.16 * squash
                pose.scaleX *= 1 + 0.14 * squash
            }
        case .spin:
            // Tour complet sur elle-même, avec un petit bond.
            let eased = 0.5 - 0.5 * cos(.pi * progress)
            pose.turn = 360 * eased
            pose.lift -= 0.12 * CGFloat(sin(.pi * progress))
        case .squish:
            // Aplatie d'un coup, puis rebond amorti comme de la gelée.
            let wobble = CGFloat(exp(-5 * progress) * cos(2 * .pi * 2.5 * progress))
            pose.scaleY *= 1 - 0.28 * wobble
            pose.scaleX *= 1 + 0.22 * wobble
        case .wiggle:
            // Dandinement amorti.
            pose.tilt += 14 * exp(-3 * progress) * sin(2 * .pi * 3 * progress)
        }
        pose.blink = 0
    }

    /// Fermeture des paupières : un aller-retour rapide toutes les `blinkInterval` secondes.
    static func blink(at t: TimeInterval) -> CGFloat {
        let phase = t.truncatingRemainder(dividingBy: blinkInterval) - (blinkInterval - blinkDuration)
        guard phase > 0 else { return 0 }
        return CGFloat(sin(.pi * phase / blinkDuration))
    }

    /// Saut en cloche de durée `duration`, répété toutes les `period` secondes (0 au sol, 1 en haut).
    static func hop(at t: TimeInterval, period: TimeInterval, duration: TimeInterval) -> CGFloat {
        let phase = t.truncatingRemainder(dividingBy: period)
        guard phase < duration else { return 0 }
        return CGFloat(sin(.pi * phase / duration))
    }
}

/// Mascotte animée en continu (respiration, clignements, mouvements propres à l'humeur).
/// `gaze` imposé (ex. suivre la souris) remplace le regard automatique. `chat` impose une attitude
/// de discussion ; avec `reactsToTap`, un clic déclenche une réaction (et un son).
struct LiveMascotView: View {
    var design: MascotDesign
    var mood: MascotMood = .idle
    var gaze: CGSize?
    var size: CGFloat = 64
    var showsBadge = true
    var chat: MascotChatPhase?
    var reactsToTap = false

    @State private var moodStart = Date()
    @State private var reaction: MascotReaction = .wiggle
    @State private var reactionStart: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            let elapsed = context.date.timeIntervalSince(moodStart)
            var pose = chat.map { MascotMotion.pose(at: elapsed, chat: $0) } ?? MascotMotion.pose(at: elapsed, mood: mood)
            let sinceTap = reactionStart.map { context.date.timeIntervalSince($0) }
            let isReacting = sinceTap.map { $0 < reaction.duration } ?? false
            if let sinceTap, isReacting { MascotMotion.apply(reaction, at: sinceTap, to: &pose) }
            // Pendant une réaction, la mascotte est ravie (yeux en arc).
            return MascotPoseView(design: design, mood: isReacting ? .happy : mood, pose: pose,
                                  gaze: gaze, size: size, showsBadge: showsBadge && !isReacting)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard reactsToTap else { return }
            reaction = reaction.next
            reactionStart = Date()
            MascotSounds.shared.play(.tap)
            Haptics.play(.snap)
        }
        .allowsHitTesting(reactsToTap)
        .onChange(of: mood) { moodStart = Date() }
        .onChange(of: chat) { moodStart = Date() }
    }
}

/// Mascotte figée dans une posture (utilisé par la vue animée et pour le rendu image par image).
struct MascotPoseView: View {
    var design: MascotDesign
    var mood: MascotMood
    var pose: MascotPose
    var gaze: CGSize?
    var size: CGFloat
    var showsBadge = true

    var body: some View {
        MascotView(design: design, mood: mood, gaze: gaze ?? pose.gaze, blink: pose.blink, size: size, showsBadge: showsBadge)
            .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
            .rotationEffect(.degrees(pose.tilt), anchor: .bottom)
            .rotation3DEffect(.degrees(pose.turn), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .offset(y: pose.lift * size)
    }
}
