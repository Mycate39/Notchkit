import EventKit
import SwiftUI

/// Compte à rebours compact : « 8 min » puis « Début ». Rafraîchi une fois par minute.
struct CalendarCountdown: View {
    let event: CalendarEvent

    var body: some View {
        TimelineView(.everyMinute) { context in
            let minutes = Int((event.start.timeIntervalSince(context.date) / 60).rounded(.up))
            Group {
                if minutes > 0 {
                    Text("\(minutes) min")
                } else {
                    Text("Début")
                }
            }
            .monospacedDigit()
            .foregroundStyle(event.color)
        }
    }
}

struct CalendarExpandedView: View {
    let module: CalendarModule
    @Environment(\.widgetSize) private var size

    var body: some View {
        Group {
            switch module.authorization {
            case .fullAccess:
                eventList
            case .notDetermined:
                permissionPrompt(
                    message: "Notchkit a besoin d'accéder à vos calendriers pour afficher vos événements.",
                    button: "Autoriser l'accès",
                    action: module.requestAccess
                )
            default:
                permissionPrompt(
                    message: "L'accès aux calendriers est refusé.",
                    button: "Ouvrir les Réglages Système",
                    action: module.openPrivacySettings
                )
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var eventList: some View {
        if module.events.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 22))
                Text("Aucun événement aujourd'hui ni demain")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(module.events.prefix(size == .small ? 2 : CalendarModule.maxEvents)) { event in
                        EventRow(event: event, now: context.date)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture { module.openCalendarApp() }
            .help("Ouvrir Calendrier")
        }
    }

    private func permissionPrompt(message: LocalizedStringKey, button: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 20))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button(button, action: action)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(event.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(timeDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(event.isOngoing(at: now) ? event.color : .white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var timeDescription: String {
        let calendar = Calendar.current
        let dayPrefix: String = {
            if calendar.isDateInToday(event.start) || event.start < now { return "" }
            if calendar.isDateInTomorrow(event.start) { return String(localized: "Demain") + " · " }
            return event.start.formatted(.dateTime.weekday(.wide)) + " · "
        }()

        if event.isAllDay {
            return dayPrefix + String(localized: "Toute la journée")
        }
        let end = event.end.formatted(date: .omitted, time: .shortened)
        if event.isOngoing(at: now) {
            return String(localized: "En cours · jusqu'à \(end)")
        }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        return dayPrefix + "\(start) – \(end)"
    }
}

struct CalendarSettingsView: View {
    @Bindable var module: CalendarModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Rappel dans l'encoche 10 minutes avant un événement", isOn: $module.showReminder)
            Toggle("Afficher les événements « journée entière »", isOn: $module.showAllDay)
            if module.authorization != .fullAccess {
                Button("Autoriser l'accès aux calendriers…") {
                    module.authorization == .notDetermined ? module.requestAccess() : module.openPrivacySettings()
                }
            }
        }
    }
}
