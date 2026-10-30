import Foundation

/// Étapes du tutoriel de bienvenue, dans l'ordre.
enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case hover
    case activities
    case files
    case agents
    case widgets
    case permissions
    case tryIt
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
        case .agents: "Suivez Claude Code depuis l'encoche"
        case .widgets: "Choisissez vos widgets"
        case .permissions: "Autorisations et démarrage"
        case .tryIt: "À vous d'essayer"
        case .done: "Tout est prêt"
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .welcome:
            "Notchkit transforme l'encoche de votre Mac en un espace vivant : musique, minuteurs, Claude Code, fichiers, widgets et bien plus. Sur un Mac sans encoche, une pastille flottante prend sa place."
        case .hover:
            "Placez le pointeur sur l'encoche : elle s'ouvre sur le lecteur de musique, et vos widgets suivent sur les pages d'après. Balayez avec deux doigts sur le trackpad pour changer de page. Éloignez le pointeur pour la refermer."
        case .activities:
            "L'activité en cours s'affiche autour de l'encoche, entourée de sa couleur ; la musique passe devant les autres, qui deviennent des bulles. Survolez une bulle pour la commander sans ouvrir l'encoche : temps restant et pause du minuteur, réponse à Claude Code. La musique reste aussi sur l'écran verrouillé."
        case .files:
            "Faites glisser des fichiers sur l'encoche. L'étagère les garde 5 minutes, le temps de les déposer ailleurs ; Convertir change leur format (image, son, vidéo, document) ; AirDrop les envoie à un appareil proche."
        case .agents:
            "La page Agents suit le travail de Claude Code : ses étapes, le fichier modifié, le terminal. Quand il demande une autorisation, sa bulle s'entoure d'ambre : survolez-la pour autoriser ou refuser, ou cliquez pour répondre dans la page. Une mascotte, à choisir parmi 33, l'accompagne."
        case .widgets:
            "Commencez avec une disposition prête à l'emploi : l'encoche prend la taille des widgets de chaque page. Vous pourrez ensuite ajouter, retirer et redimensionner chaque widget dans les réglages, et choisir dans Apparence un fond noir ou en verre."
        case .permissions:
            "Notchkit ne demande une autorisation que lorsqu'une fonction en a besoin, et toutes sont facultatives. L'Accessibilité est la plus utile : donnez-la dès maintenant."
        case .tryIt:
            "Faites ces gestes sur la vraie encoche, en haut de l'écran. Chacun se coche tout seul."
        case .done:
            "Notchkit est prêt. Vous retrouverez les réglages et ce tutoriel dans le menu Notchkit de la barre des menus ; les réglages aussi sous la roue dentée de l'encoche ouverte."
        }
    }
}

/// Gestes de l'essai guidé, faits sur la vraie encoche et cochés dès qu'ils sont détectés.
enum OnboardingTrialTask: String, CaseIterable, Identifiable, Sendable {
    case open
    case swipe
    case drop
    case pause

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .open: "Ouvrez l'encoche"
        case .swipe: "Changez de page"
        case .drop: "Déposez un fichier sur l'étagère"
        case .pause: "Mettez un minuteur en pause"
        }
    }

    var hint: LocalizedStringResource {
        switch self {
        case .open: "Placez le pointeur dessus."
        case .swipe: "Encoche ouverte, balayez avec deux doigts."
        case .drop: "Faites glisser ce fichier sur l'encoche, puis sur « Garder dans l'étagère »."
        case .pause: "Lancez-en un, puis survolez-le ou ouvrez l'encoche."
        }
    }

    /// Délai après l'ouverture de l'encoche pendant lequel un changement de page vient de l'ouverture
    /// (page de l'activité en cours), pas d'un balayage.
    static let openingPageChangeWindow: TimeInterval = 0.5

    /// Changement de page fait par la personne (fonction pure, testée).
    static func isSwipe(openedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(openedAt) > openingPageChangeWindow
    }

    /// Gestes possibles avec la configuration actuelle (fonction pure, testée) : changer de page
    /// demande au moins deux pages, et l'étagère et les minuteurs peuvent être désactivés.
    static func available(pageCount: Int, hasShelf: Bool, hasTimers: Bool) -> [OnboardingTrialTask] {
        allCases.filter { task in
            switch task {
            case .open: true
            case .swipe: pageCount >= 2
            case .drop: hasShelf
            case .pause: hasTimers
            }
        }
    }
}
