import SwiftUI

/// Importance d'un module pour l'affichage compact (encoche repliée).
/// Le gestionnaire affiche le module ayant la priorité la plus haute ;
/// à priorité égale, c'est l'ordre choisi par l'utilisateur qui l'emporte.
enum ModulePriority: Int, Comparable, Sendable {
    /// Rien à afficher en mode compact.
    case none = 0
    /// Information de fond (ex. l'heure).
    case low = 10
    /// Activité en cours (ex. musique en lecture).
    case normal = 50
    /// Information urgente (ex. minuteur qui se termine).
    case high = 100

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Services mis à disposition des modules par l'application.
@MainActor
struct ModuleContext {
    /// Affiche une alerte temporaire dans l'encoche (ex. branchement du chargeur).
    let presentAlert: @MainActor (NotchAlert) -> Void
}

/// Protocole commun à toutes les fonctionnalités de Notchkit.
///
/// Cycle de vie :
/// 1. le `ModuleManager` crée le module avec `init(context:)` quand il est activé ;
/// 2. il appelle `start()` : le module s'abonne à ses sources de données ;
/// 3. à la désactivation, il appelle `stop()` : le module doit tout libérer
///    (observateurs, timers…) pour ne plus consommer ni CPU ni batterie.
///
/// Les modules sont des classes `@Observable` : les vues se mettent à jour
/// automatiquement quand leurs propriétés changent.
@MainActor
protocol NotchModule: AnyObject, Observable {
    static var descriptor: ModuleDescriptor { get }

    init(context: ModuleContext)

    func start()
    func stop()

    /// Priorité actuelle en mode compact. `.none` = le module ne demande pas d'affichage.
    var compactPriority: ModulePriority { get }

    /// Contenu affiché à gauche de l'encoche quand elle est repliée.
    func compactLeading() -> AnyView?
    /// Contenu affiché à droite de l'encoche quand elle est repliée.
    func compactTrailing() -> AnyView?
    /// Contenu affiché quand l'encoche est dépliée.
    func expandedView() -> AnyView
    /// Largeur relative de la carte dans l'encoche dépliée (1 = normale, 2 = double).
    var expandedWidthWeight: CGFloat { get }
    /// Réglages propres au module (affichés dans l'onglet « Modules »).
    func settingsView() -> AnyView?
}

// Implémentations par défaut : un module n'implémente que ce dont il a besoin.
extension NotchModule {
    var moduleID: String { Self.descriptor.id }

    func start() {}
    func stop() {}
    func compactLeading() -> AnyView? { nil }
    func compactTrailing() -> AnyView? { nil }
    func settingsView() -> AnyView? { nil }
    var expandedWidthWeight: CGFloat { 1 }
}
