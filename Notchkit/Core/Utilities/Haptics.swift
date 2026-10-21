import AppKit

/// Retour haptique du trackpad Force Touch (API publique `NSHapticFeedbackManager`).
/// Ressenti seulement si le doigt est posé sur un trackpad Force Touch.
@MainActor
enum Haptics {
    /// Activé dans les réglages (Général > Retour haptique).
    static var isEnabled = true

    /// Motifs du trackpad, selon leur sens dans les HIG d'Apple : chaque vibration répond à un geste.
    enum Kind {
        /// Générique : ouverture de l'encoche, appui sur un bouton, clic sur la mascotte.
        case tap
        /// Changement de niveau : cran de volume ou de luminosité, minute de la règle du minuteur.
        case step
        /// Alignement : un élément se cale à sa place (page, zone de dépôt, ancrage, bout de la règle).
        case snap
    }

    static func play(_ kind: Kind) {
        guard isEnabled, !AutomatedRun.isActive else { return }
        let pattern: NSHapticFeedbackManager.FeedbackPattern = switch kind {
        case .tap: .generic
        case .step: .levelChange
        case .snap: .alignment
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
