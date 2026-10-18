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
/// `gaze` imposé (ex. suivre la souris) remplace le regard automatique.
struct LiveMascotView: View {
    var design: MascotDesign
    var mood: MascotMood = .idle
    var gaze: CGSize?
    var size: CGFloat = 64

    @State private var moodStart = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            let pose = MascotMotion.pose(at: context.date.timeIntervalSince(moodStart), mood: mood)
            MascotPoseView(design: design, mood: mood, pose: pose, gaze: gaze, size: size)
        }
        .onChange(of: mood) { moodStart = Date() }
    }
}

/// Mascotte figée dans une posture (utilisé par la vue animée et pour le rendu image par image).
struct MascotPoseView: View {
    var design: MascotDesign
    var mood: MascotMood
    var pose: MascotPose
    var gaze: CGSize?
    var size: CGFloat

    var body: some View {
        MascotView(design: design, mood: mood, gaze: gaze ?? pose.gaze, blink: pose.blink, size: size)
            .scaleEffect(x: pose.scaleX, y: pose.scaleY, anchor: .bottom)
            .rotationEffect(.degrees(pose.tilt), anchor: .bottom)
            .offset(y: pose.lift * size)
    }
}
