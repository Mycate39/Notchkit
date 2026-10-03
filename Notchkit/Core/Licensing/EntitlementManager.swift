import Foundation

/// Décide quels modules sont accessibles.
///
/// Aujourd'hui l'app est entièrement gratuite : tout est débloqué.
/// Le jour où une version payante existera, seule cette classe devra changer
/// (vérification d'un achat, d'une licence…), le reste de l'app ne bouge pas.
@MainActor
final class EntitlementManager {
    var hasProAccess: Bool { true }

    func isUnlocked(_ descriptor: ModuleDescriptor) -> Bool {
        descriptor.tier == .free || hasProAccess
    }
}
