#if DEBUG
import Foundation

/// Scénario d'un tournage de démonstration (fichier JSON passé dans `NOTCHKIT_DEMO`).
///
/// ```json
/// { "duration": 28, "region": { "width": 900, "height": 260 },
///   "steps": [ { "at": 3.0, "do": "unlock" },
///              { "at": 7.7, "do": "music.play", "title": "danker", "artist": "Gabester" } ] }
/// ```
/// `at` : secondes depuis le début de l'enregistrement. Actions reconnues : voir `DemoDirector.perform`.
struct DemoScenario: Decodable {
    struct Region: Decodable {
        /// Zone filmée, en points, centrée sur l'encoche et collée au haut de l'écran.
        var width: Double = 900
        var height: Double = 260
    }

    struct Step: Decodable {
        let at: Double
        let action: String
        // Paramètres facultatifs, selon l'action
        var title: String?
        var artist: String?
        var minutes: Double?
        var module: String?
        var hidden: Bool?
        var project: String?
        var file: String?
        var old: String?
        var new: String?
        var command: String?
        var description: String?
        var prompt: String?
        /// Niveau (0…1 : volume, luminosité ; 0…100 : batterie), page, heure, valeur libre, liste
        var level: Double?
        var page: Int?
        var hour: Int?
        var value: String?
        var items: [String]?
        var pages: [[String]]?
        var sizes: [String: String]?

        enum CodingKeys: String, CodingKey {
            case at, action = "do", title, artist, minutes, module, hidden, project, file, old, new, command, description, prompt
            case level, page, hour, value, items, pages, sizes
        }
    }

    /// Réglages du film : modules activés, disposition des pages et apparence de départ.
    struct Setup: Decodable {
        var modules: [String]?
        var pages: [[String]]?
        var sizes: [String: String]?
        /// Couleur d'accent `#RRGGBB`, fond (`black`, `glass`), mascotte
        var accent: String?
        var background: String?
        var mascot: String?
        /// Style d'animation (`fluid`, `quick`, `bouncy`, `none`)
        var animation: String?
    }

    var duration: Double
    var region = Region()
    var fps = 60
    var steps: [Step]
    var setup: Setup?

    enum CodingKeys: String, CodingKey { case duration, region, fps, steps, setup }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.decode(Double.self, forKey: .duration)
        region = try container.decodeIfPresent(Region.self, forKey: .region) ?? Region()
        fps = try container.decodeIfPresent(Int.self, forKey: .fps) ?? 60
        steps = try container.decode([Step].self, forKey: .steps).sorted { $0.at < $1.at }
        setup = try container.decodeIfPresent(Setup.self, forKey: .setup)
    }

    /// Scénario du tournage en cours (`NOTCHKIT_DEMO`), lu au lancement pour préparer les réglages.
    static var current: DemoScenario? {
        guard let path = ProcessInfo.processInfo.environment["NOTCHKIT_DEMO"],
              let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(DemoScenario.self, from: data)
    }
}

/// Réglages jetables d'un tournage : copie de ceux de l'utilisateur dans un domaine à part, avec
/// seulement les modules du film. Rien n'est écrit dans les vrais réglages ; le domaine est effacé
/// à la fin.
@MainActor
enum DemoSettings {
    static let suiteName = "com.andeolchenaux.notchkit.demo"
    static let storageKey = "notchkit.settings.v1"
    /// Modules montrés dans les films (sauf liste du scénario) ; tous les autres sont coupés pour ne
    /// pas parasiter l'encoche.
    static let defaultModules: Set<String> = ["music", "activities", "agents", "unlock"]

    static let defaults: UserDefaults = {
        let demo = UserDefaults(suiteName: suiteName) ?? .standard
        demo.removePersistentDomain(forName: suiteName)
        var settings = UserDefaults.standard.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
        let setup = DemoScenario.current?.setup
        let modules = setup?.modules.map(Set.init) ?? defaultModules
        for type in ModuleRegistry.allModules {
            settings.moduleEnabled[type.descriptor.id] = modules.contains(type.descriptor.id)
        }
        if let setup { apply(setup, to: &settings) }
        settings.onboardingCompleted = true
        settings.hapticsEnabled = false
        settings.mascotSounds = false
        settings.showsMenuBarIcon = false
        if let data = try? JSONEncoder().encode(settings) { demo.set(data, forKey: storageKey) }
        return demo
    }()

    /// Disposition et apparence demandées par le scénario (aussi appliquées en cours de film).
    static func apply(_ setup: DemoScenario.Setup, to settings: inout AppSettings) {
        if let pages = setup.pages {
            let sizes = (setup.sizes ?? [:]).compactMapValues(WidgetSize.init(rawValue:))
            settings.widgetLayout = WidgetLayout(pages: pages, sizes: sizes)
        }
        if let accent = setup.accent.flatMap(storedColor) { settings.appearance.accent = accent }
        if let background = setup.background.flatMap(NotchAppearance.Background.init(rawValue:)) {
            settings.appearance.background = background
        }
        if let mascot = setup.mascot.flatMap(MascotDesign.init(rawValue:)) { settings.mascot = mascot }
        if let animation = setup.animation.flatMap(NotchAppearance.AnimationStyle.init(rawValue:)) {
            settings.appearance.animation = animation
        }
    }

    /// `#RRGGBB` → couleur enregistrable.
    static func storedColor(_ hex: String) -> StoredColor? {
        guard let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) else { return nil }
        return StoredColor(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                           blue: Double(value & 0xFF) / 255)
    }

    static func discard() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}
#endif
