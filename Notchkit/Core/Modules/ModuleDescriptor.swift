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
    /// Module « contextuel » : il tourne même quand son widget est masqué, et s'affiche alors en
    /// dernière page de l'encoche tant qu'il a du contenu (`NotchModule.hasContextualContent`).
    var contextual = false
    /// Animations déclenchées par le système (branchement du chargeur, AirPods, touches de volume) :
    /// elles fonctionnent même widget désactivé. Le module tourne alors en arrière-plan, sans carte ni
    /// activité dans l'encoche repliée ; l'interrupteur des réglages ne règle que l'affichage du widget.
    var backgroundEvents = false
    /// Widget pleine page : il occupe toujours une page entière à lui seul, en une seule taille.
    var fullPage = false
    /// Moteur d'un autre module (son identifiant) : il tourne quand celui-ci est activé et n'apparaît
    /// pas dans les réglages (ex. Claude Code, moteur de la page Agents).
    var companionOf: String?
}
