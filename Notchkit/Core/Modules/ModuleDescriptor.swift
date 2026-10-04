import Foundation

/// Catégorie d'un module, utilisée pour les regrouper dans l'écran de réglages.
enum ModuleCategory: String, CaseIterable, Identifiable, Sendable {
    case media
    case system
    case widgets
    case productivity

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .media: "Médias"
        case .system: "Système"
        case .widgets: "Widgets"
        case .productivity: "Productivité"
        }
    }
}

/// Niveau d'accès d'un module.
/// Prépare une future version payante : un module `.pro` ne sera chargé que si
/// l'`EntitlementManager` l'autorise. Aujourd'hui, tout est débloqué.
enum ModuleTier: String, Sendable {
    case free
    case pro
}

/// Métadonnées statiques d'un module : tout ce qu'il faut pour l'afficher
/// dans les réglages sans avoir à l'instancier.
struct ModuleDescriptor: Identifiable, Sendable {
    /// Identifiant stable (sert de clé de sauvegarde, ne jamais le changer).
    let id: String
    let name: LocalizedStringResource
    let summary: LocalizedStringResource
    /// Nom d'un SF Symbol.
    let systemImage: String
    let category: ModuleCategory
    let tier: ModuleTier
    /// État par défaut lors du premier lancement.
    let defaultEnabled: Bool
    /// Faux pour un module qui fonctionne en arrière-plan sans carte dans l'encoche dépliée
    /// (ex. animations de déverrouillage) : il n'apparaît ni dans les pages ni dans l'éditeur.
    var providesWidget = true
}
