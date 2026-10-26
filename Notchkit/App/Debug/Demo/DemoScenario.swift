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

        enum CodingKeys: String, CodingKey {
            case at, action = "do", title, artist, minutes, module, hidden, project, file, old, new, command, description, prompt
        }
    }

    var duration: Double
    var region = Region()
    var fps = 60
    var steps: [Step]

    enum CodingKeys: String, CodingKey { case duration, region, fps, steps }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.decode(Double.self, forKey: .duration)
        region = try container.decodeIfPresent(Region.self, forKey: .region) ?? Region()
        fps = try container.decodeIfPresent(Int.self, forKey: .fps) ?? 60
        steps = try container.decode([Step].self, forKey: .steps).sorted { $0.at < $1.at }
    }
}

/// Réglages jetables d'un tournage : copie de ceux de l'utilisateur dans un domaine à part, avec
/// seulement les modules du film. Rien n'est écrit dans les vrais réglages ; le domaine est effacé
/// à la fin.
@MainActor
enum DemoSettings {
    static let suiteName = "com.andeolchenaux.notchkit.demo"
    static let storageKey = "notchkit.settings.v1"
    /// Modules montrés dans les films ; tous les autres sont coupés pour ne pas parasiter l'encoche.
    static let modules: Set<String> = ["music", "activities", "agents", "unlock"]

    static let defaults: UserDefaults = {
        let demo = UserDefaults(suiteName: suiteName) ?? .standard
        demo.removePersistentDomain(forName: suiteName)
        var settings = UserDefaults.standard.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
        for type in ModuleRegistry.allModules {
            settings.moduleEnabled[type.descriptor.id] = modules.contains(type.descriptor.id)
        }
        settings.onboardingCompleted = true
        settings.hapticsEnabled = false
        settings.mascotSounds = false
        settings.showsMenuBarIcon = false
        if let data = try? JSONEncoder().encode(settings) { demo.set(data, forKey: storageKey) }
        return demo
    }()

    static func discard() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}
#endif
