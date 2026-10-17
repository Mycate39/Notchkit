import Foundation

/// Étapes du tutoriel de bienvenue, dans l'ordre.
enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case hover
    case activities
    case files
    case widgets
    case permissions
    case done

    var id: Int { rawValue }

    /// Étape suivante, ou `nil` à la fin (fonction pure, testée).
    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    /// Étape précédente, ou `nil` au début.
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    var isFirst: Bool { previous == nil }
    var isLast: Bool { next == nil }

    var title: LocalizedStringResource {
        switch self {
        case .welcome: "Bienvenue dans Notchkit"
        case .hover: "Survolez l'encoche pour l'ouvrir"
        case .activities: "Vos activités vivent dans l'encoche"
        case .files: "Déposez des fichiers sur l'encoche"
        case .widgets: "Choisissez vos widgets"
        case .permissions: "Autorisations et démarrage"
        case .done: "Tout est prêt"
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .welcome:
            "Notchkit transforme l'encoche de votre Mac en un espace vivant : musique, minuteurs, batterie, météo, calendrier et bien plus. Sur un Mac sans encoche, une pastille flottante prend sa place."
        case .hover:
            "Placez le pointeur sur l'encoche : elle se déplie et affiche vos widgets. Balayez avec deux doigts ou cliquez sur les onglets pour changer de page. Éloignez le pointeur pour la refermer."
        case .activities:
            "Quand une musique joue, qu'un minuteur tourne ou que Claude Code travaille, l'activité s'affiche de part et d'autre de l'encoche. S'il y en a plusieurs, les autres deviennent des bulles : cliquez dessus pour les ouvrir."
        case .files:
            "Faites glisser des fichiers sur l'encoche : déposez-les sur l'étagère pour les garder sous la main, ou sur AirDrop pour les envoyer à un appareil proche."
        case .widgets:
            "Commencez avec une disposition prête à l'emploi. Vous pourrez ensuite ajouter, retirer et redimensionner chaque widget dans les réglages."
        case .permissions:
            "L'autorisation Accessibilité permet d'afficher le volume et la luminosité quand vous utilisez les touches du clavier, et d'éviter que l'encoche cache les menus. Elle est facultative."
        case .done:
            "Notchkit est prêt. Vous retrouverez les réglages et ce tutoriel dans le menu Notchkit de la barre des menus."
        }
    }
}
