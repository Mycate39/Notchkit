import AppKit
import EventKit
import SwiftUI
import Observation

/// Module Calendrier : prochains événements (aujourd'hui et demain) et rappel dans l'encoche
/// quelques minutes avant un rendez-vous.
///
/// API publique EventKit. L'accès au calendrier n'est demandé que lorsque l'utilisateur
/// clique sur « Autoriser » dans la carte (pas de demande surprise au lancement).
@MainActor
@Observable
final class CalendarModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "calendar",
        name: "Calendrier",
        summary: "Prochains événements et rappel avant un rendez-vous.",
        systemImage: "calendar",
        category: .productivity,
        tier: .free,
        defaultEnabled: true
    )

    /// Nombre maximal d'événements affichés dans la carte.
    static let maxEvents = 3

    private(set) var authorization: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var events: [CalendarEvent] = []
    private(set) var reminderEvent: CalendarEvent?

    // MARK: Réglages du module

    /// Affiche un rappel dans l'encoche repliée 10 minutes avant un événement.
    var showReminder: Bool {
        didSet { UserDefaults.standard.set(showReminder, forKey: Keys.showReminder) }
    }
    /// Affiche les événements « journée entière ».
    var showAllDay: Bool {
        didSet {
            UserDefaults.standard.set(showAllDay, forKey: Keys.showAllDay)
            reload()
        }
    }

    private enum Keys {
        static let showReminder = "module.calendar.showReminder"
        static let showAllDay = "module.calendar.showAllDay"
    }

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var boundaryTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false

    init(context: ModuleContext) {
        let defaults = UserDefaults.standard
        showReminder = defaults.object(forKey: Keys.showReminder) as? Bool ?? true
        showAllDay = defaults.object(forKey: Keys.showAllDay) as? Bool ?? true
    }

    // MARK: Cycle de vie

    func start() {
        guard !isStarted else { return }
        isStarted = true
        authorization = EKEventStore.authorizationStatus(for: .event)

        // Calendrier modifié (ajout, synchronisation iCloud…), réveil du Mac, changement de jour.
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })

        reload()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        boundaryTask?.cancel()
        boundaryTask = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        events = []
        reminderEvent = nil
    }

    // MARK: Autorisation

    func requestAccess() {
        NSApp.activate()
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.authorization = EKEventStore.authorizationStatus(for: .event)
                    self?.reload()
                }
            }
        }
    }

    /// Ouvre Réglages Système > Confidentialité > Calendriers (accès refusé auparavant).
    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: Chargement

    private func reload() {
        guard isStarted else { return }
        guard authorization == .fullAccess else {
            events = []
            reminderEvent = nil
            return
        }

        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        // Aujourd'hui et demain.
        let end = calendar.date(byAdding: .day, value: 2, to: startOfToday) ?? now.addingTimeInterval(2 * 86_400)
        let predicate = store.predicateForEvents(withStart: startOfToday, end: end, calendars: nil)

        let all = store.events(matching: predicate)
            .filter { showAllDay || !$0.isAllDay }
            .map { event in
                CalendarEvent(
                    // L'identifiant est partagé par toutes les occurrences d'un événement récurrent.
                    id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                    title: event.title?.isEmpty == false ? event.title : String(localized: "Sans titre"),
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    color: event.calendar.map { Color(cgColor: $0.cgColor) } ?? .accentColor,
                    calendarTitle: event.calendar?.title ?? ""
                )
            }

        let upcoming = CalendarSchedule.upcoming(all, at: now, limit: Self.maxEvents)
        if upcoming != events { events = upcoming }
        let reminder = CalendarSchedule.reminderEvent(in: all, at: now)
        if reminder != reminderEvent { reminderEvent = reminder }

        scheduleNextReload(after: now, events: all)
    }

    private func scheduleNextReload(after now: Date, events: [CalendarEvent]) {
        boundaryTask?.cancel()
        let next = CalendarSchedule.nextBoundary(after: now, events: events)
        let delay = max(1, next.timeIntervalSince(now))
        boundaryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    // MARK: Affichage

    var compactPriority: ModulePriority {
        // Un rendez-vous imminent passe avant la musique.
        showReminder && reminderEvent != nil ? .high : .none
    }

    var expandedWidthWeight: CGFloat { 2 }

    func compactLeading() -> AnyView? {
        guard let event = reminderEvent else { return nil }
        return AnyView(
            Image(systemName: "calendar")
                .foregroundStyle(event.color)
        )
    }

    func compactTrailing() -> AnyView? {
        guard let event = reminderEvent else { return nil }
        return AnyView(CalendarCountdown(event: event))
    }

    func expandedView() -> AnyView {
        AnyView(CalendarExpandedView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(CalendarSettingsView(module: self))
    }
}
