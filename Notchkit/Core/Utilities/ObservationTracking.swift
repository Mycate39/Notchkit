import Foundation
import Observation

/// Exécute `action` à chaque changement d'une des propriétés observables lues dans `read`.
///
/// `withObservationTracking` ne prévient qu'une seule fois : on se réabonne donc après
/// chaque notification. La boucle s'arrête d'elle-même quand `read` ne lit plus rien
/// (typiquement quand l'objet référencé faiblement a disparu).
@MainActor
func trackChanges(
    of read: @escaping @MainActor @Sendable () -> Void,
    perform action: @escaping @MainActor @Sendable () -> Void
) {
    withObservationTracking {
        read()
    } onChange: {
        // `onChange` est appelé juste AVANT la modification : on attend le tour suivant
        // pour lire les nouvelles valeurs.
        Task { @MainActor in
            action()
            trackChanges(of: read, perform: action)
        }
    }
}
