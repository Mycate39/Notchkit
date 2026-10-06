import Foundation

/// Écran sur lequel afficher l'encoche.
enum ScreenSelection: Codable, Hashable, Sendable {
    /// Écran principal (celui qui porte la barre des menus).
    case primary
    /// Écran précis, identifié par son UUID (stable entre les redémarrages).
    /// Le nom sert uniquement à l'affichage quand l'écran est débranché.
    case specific(id: String, name: String)

    // Deux sélections sont identiques si elles désignent le même écran, même si son nom a changé.
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.primary, .primary): true
        case let (.specific(a, _), .specific(b, _)): a == b
        default: false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .primary: hasher.combine(0)
        case let .specific(id, _): hasher.combine(id)
        }
    }
}

/// Ensemble des réglages de l'application, sauvegardés en JSON.
struct AppSettings: Codable, Equatable, Sendable {
    /// État activé/désactivé choisi par l'utilisateur, par identifiant de module.
    /// Un module absent utilise son `defaultEnabled`.
    var moduleEnabled: [String: Bool] = [:]
    /// Ordre de priorité des modules (identifiants).
    var moduleOrder: [String] = []
    var screenSelection: ScreenSelection = .primary
    /// Affiche une fausse encoche sur les écrans qui n'en ont pas (utile pour tester).
    var simulateNotch = false
    /// Délai avant de déplier l'encoche au survol (secondes).
    var hoverOpenDelay: Double = 0.12
    /// Délai avant de replier l'encoche quand la souris s'éloigne (secondes).
    var hoverCloseDelay: Double = 0.35
    /// Disposition des widgets choisie par l'utilisateur (`nil` = automatique).
    var widgetLayout: WidgetLayout?
    /// Apparence de l'encoche (taille, animations, couleurs).
    var appearance = NotchAppearance()
    /// Retour haptique du trackpad (ouverture, pages, alertes…).
    var hapticsEnabled = true
    /// Décale l'encoche (simulée ou pastille) pour ne pas cacher les menus de l'app active.
    var avoidAppMenus = true

    init() {}

    // Décodage tolérant : une clé manquante (ex. réglage ajouté dans une nouvelle version)
    // reprend sa valeur par défaut au lieu de faire perdre tous les réglages.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        moduleEnabled = try c.decodeIfPresent([String: Bool].self, forKey: .moduleEnabled) ?? d.moduleEnabled
        moduleOrder = try c.decodeIfPresent([String].self, forKey: .moduleOrder) ?? d.moduleOrder
        screenSelection = try c.decodeIfPresent(ScreenSelection.self, forKey: .screenSelection) ?? d.screenSelection
        simulateNotch = try c.decodeIfPresent(Bool.self, forKey: .simulateNotch) ?? d.simulateNotch
        hoverOpenDelay = try c.decodeIfPresent(Double.self, forKey: .hoverOpenDelay) ?? d.hoverOpenDelay
        hoverCloseDelay = try c.decodeIfPresent(Double.self, forKey: .hoverCloseDelay) ?? d.hoverCloseDelay
        widgetLayout = try? c.decodeIfPresent(WidgetLayout.self, forKey: .widgetLayout)
        appearance = (try? c.decodeIfPresent(NotchAppearance.self, forKey: .appearance)) ?? d.appearance
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? d.hapticsEnabled
        avoidAppMenus = try c.decodeIfPresent(Bool.self, forKey: .avoidAppMenus) ?? d.avoidAppMenus
    }
}
