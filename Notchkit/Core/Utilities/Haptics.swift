import AppKit

/// Retour haptique du trackpad Force Touch (API publique `NSHapticFeedbackManager`).
/// Ressenti seulement si le doigt est posé sur un trackpad Force Touch.
@MainActor
enum Haptics {
    /// Activé dans les réglages (Général > Retour haptique).
    static var isEnabled = true

    enum Kind {
        /// Ouverture de l'encoche, alerte.
        case tap
        /// Changement de page, cran de volume ou de luminosité.
        case step
        /// Passage d'une zone à l'autre (glisser-déposer).
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
