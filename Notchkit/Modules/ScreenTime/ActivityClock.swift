import CoreGraphics
import Foundation

/// Activité de l'utilisateur, déduite du temps écoulé depuis le dernier événement clavier, souris ou
/// trackpad (API publique, sans lire aucune frappe ni aucun contenu).
enum ActivityClock {
    /// Au-delà de 2 minutes sans événement, l'utilisateur n'est plus compté comme actif.
    static let idleThreshold: TimeInterval = 120
    /// 5 minutes sans événement comptent comme une pause.
    static let pauseThreshold: TimeInterval = 5 * 60

    static var secondsSinceLastInput: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    static func isActive(idle: TimeInterval) -> Bool { idle < idleThreshold }

    /// Début de la période d'activité continue : remis à zéro par une pause, démarré à la reprise.
    static func streakStart(previous: Date?, idle: TimeInterval, now: Date) -> Date? {
        if idle >= pauseThreshold { return nil }
        return previous ?? now.addingTimeInterval(-idle)
    }

    /// Clé du jour (« 2026-10-09 »), dans le fuseau local.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Temps passé par app et par jour, gardé sur ce Mac uniquement (Application Support).
struct ScreenTimeLog: Codable, Equatable, Sendable {
    /// Jour → identifiant d'app → secondes.
    var days: [String: [String: Double]] = [:]

    static let keptDays = 30

    mutating func add(_ seconds: Double, app: String, day: String) {
        days[day, default: [:]][app, default: 0] += seconds
    }

    func total(day: String) -> Double {
        days[day]?.values.reduce(0, +) ?? 0
    }

    func topApps(day: String, limit: Int = 5) -> [(app: String, seconds: Double)] {
        (days[day] ?? [:]).sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }

    /// Ne garde que les derniers jours (les clés « aaaa-mm-jj » se trient dans l'ordre chronologique).
    mutating func prune(keeping count: Int = keptDays) {
        let keys = days.keys.sorted()
        for key in keys.dropLast(count) { days[key] = nil }
    }
}
