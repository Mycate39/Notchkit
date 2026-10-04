import SwiftUI

/// Événement de calendrier, indépendant d'EventKit (facile à tester et à afficher).
struct CalendarEvent: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let calendarTitle: String

    func isOngoing(at date: Date) -> Bool {
        start <= date && date < end
    }
}

/// Règles de calendrier : quels événements afficher, quand rappeler, quand se réveiller.
enum CalendarSchedule {
    /// Le rappel apparaît 10 minutes avant le début…
    static let reminderLead: TimeInterval = 10 * 60
    /// … et disparaît 1 minute après.
    static let reminderTail: TimeInterval = 60

    /// Événements pas encore terminés, triés : journées entières d'abord, puis par heure de début.
    static func upcoming(_ events: [CalendarEvent], at now: Date, limit: Int) -> [CalendarEvent] {
        Array(
            events
                .filter { $0.end > now }
                .sorted { lhs, rhs in
                    if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                    return lhs.start < rhs.start
                }
                .prefix(limit)
        )
    }

    /// Événement (hors journée entière) qui commence bientôt ou vient de commencer.
    static func reminderEvent(in events: [CalendarEvent], at now: Date) -> CalendarEvent? {
        events
            .filter { !$0.isAllDay && now >= $0.start - reminderLead && now < $0.start + reminderTail }
            .min { $0.start < $1.start }
    }

    /// Prochain instant où l'affichage doit changer (début/fin de rappel, début/fin d'événement,
    /// minuit). On ne se réveille qu'à ces moments-là : aucun relevé périodique.
    static func nextBoundary(after now: Date, events: [CalendarEvent], calendar: Calendar = .current) -> Date {
        var candidates: [Date] = []
        for event in events {
            candidates.append(event.end)
            if !event.isAllDay {
                candidates.append(event.start - reminderLead)
                candidates.append(event.start)
                candidates.append(event.start + reminderTail)
            }
        }
        if let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) {
            candidates.append(midnight)
        }
        return candidates.filter { $0 > now }.min() ?? now.addingTimeInterval(3600)
    }
}
