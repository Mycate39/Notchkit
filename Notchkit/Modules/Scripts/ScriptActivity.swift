import SwiftUI

/// Demande reçue de la commande `notchkit` (formulaire ou JSON envoyé au serveur local).
struct ScriptRequest: Equatable, Sendable {
    enum Action: String, Sendable {
        case notify, start, progress, end
        /// Mode capot fermé : `value` vaut `on`, `off` ou une durée en minutes.
        case awake
    }

    let action: Action
    let id: String
    let title: String?
    let message: String?
    let symbol: String?
    let color: String?
    /// Avancement de 0 à 1 (reçu de 0 à 100).
    let progress: Double?
    /// Fin d'une activité : réussie (vrai) ou en échec (faux).
    let succeeded: Bool
    /// `notchkit run --awake` : le Mac reste éveillé capot fermé tant que la commande tourne.
    let keepsAwake: Bool
    /// `notchkit awake` : `on`, `off` ou une durée en minutes.
    let value: String?

    /// Lit les champs envoyés. `nil` si l'action est inconnue.
    init?(fields: [String: Any]) {
        func text(_ key: String) -> String? {
            guard let value = (fields[key] as? String) ?? (fields[key] as? NSNumber)?.stringValue else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(ScriptActivity.maxTextLength))
        }
        guard let raw = text("action"), let action = Action(rawValue: raw.lowercased()) else { return nil }
        self.action = action
        id = text("id") ?? "default"
        title = text("title")
        message = text("message")
        symbol = text("symbol")
        color = text("color")
        progress = text("progress").flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
            .map { min(max($0 / 100, 0), 1) }
        succeeded = !["failure", "failed", "error", "fail", "echec", "échec"].contains(text("status")?.lowercased() ?? "")
        keepsAwake = ["1", "true", "yes", "on"].contains(text("awake")?.lowercased() ?? "")
        value = text("value")
    }
}

/// Activité en cours lancée par un script (`notchkit start` ou `notchkit run`).
struct ScriptActivity: Identifiable, Equatable, Sendable {
    static let maxTextLength = 120
    /// Une activité sans nouvelles depuis une heure disparaît (script interrompu sans `end`).
    static let staleInterval: TimeInterval = 3600

    let id: String
    var title: String
    var symbol: String
    var colorName: String?
    var progress: Double?
    let startedAt: Date
    var updatedAt: Date

    var color: Color { ScriptPalette.color(named: colorName) ?? .cyan }
}

/// Couleurs reconnues par `--color` (noms anglais et français).
enum ScriptPalette {
    static func color(named name: String?) -> Color? {
        switch name?.lowercased() {
        case "red", "rouge": .red
        case "orange": .orange
        case "yellow", "jaune": .yellow
        case "green", "vert": .green
        case "mint", "menthe": .mint
        case "teal", "cyan": .cyan
        case "blue", "bleu": .blue
        case "indigo": .indigo
        case "purple", "violet": .purple
        case "pink", "rose": .pink
        case "gray", "grey", "gris": .gray
        case "white", "blanc": .white
        default: nil
        }
    }
}

/// Suivi des activités des scripts (logique pure, testée).
struct ScriptActivityTracker: Equatable, Sendable {
    /// Ce que l'encoche doit montrer après une demande.
    enum Outcome: Equatable, Sendable {
        case none
        case notification(title: String, message: String?, symbol: String, colorName: String?)
        case finished(title: String, message: String?, succeeded: Bool, duration: TimeInterval?)
    }

    static let maxActivities = 8

    private(set) var activities: [String: ScriptActivity] = [:]

    /// Activités, de la plus récente à la plus ancienne.
    var ordered: [ScriptActivity] {
        activities.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    mutating func apply(_ request: ScriptRequest, at date: Date = Date()) -> Outcome {
        switch request.action {
        case .notify:
            return .notification(title: request.title ?? request.message ?? String(localized: "Notification"),
                                 message: request.title == nil ? nil : request.message,
                                 symbol: request.symbol ?? "bell.fill", colorName: request.color)

        case .start, .progress:
            var activity = activities[request.id] ?? ScriptActivity(
                id: request.id, title: request.title ?? request.id, symbol: request.symbol ?? "terminal",
                colorName: request.color, progress: nil, startedAt: date, updatedAt: date)
            if let title = request.title { activity.title = title }
            if let symbol = request.symbol { activity.symbol = symbol }
            if let color = request.color { activity.colorName = color }
            if let progress = request.progress { activity.progress = progress }
            activity.updatedAt = date
            activities[request.id] = activity
            // Au-delà du maximum, la plus ancienne s'efface.
            if activities.count > Self.maxActivities, let oldest = activities.values.min(by: { $0.updatedAt < $1.updatedAt }) {
                activities[oldest.id] = nil
            }
            return .none

        case .awake:
            return .none

        case .end:
            let activity = activities.removeValue(forKey: request.id)
            return .finished(title: request.title ?? activity?.title ?? request.id,
                             message: request.message,
                             succeeded: request.succeeded,
                             duration: activity.map { date.timeIntervalSince($0.startedAt) })
        }
    }

    mutating func expireStale(at date: Date = Date()) {
        activities = activities.filter { date.timeIntervalSince($0.value.updatedAt) < ScriptActivity.staleInterval }
    }

    /// Durée lisible : « 42 s », « 3 min 05 », « 1 h 02 ».
    static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return String(localized: "\(total) s") }
        if total < 3600 { return String(localized: "\(total / 60) min \(String(format: "%02d", total % 60))") }
        return String(localized: "\(total / 3600) h \(String(format: "%02d", total % 3600 / 60))")
    }
}
