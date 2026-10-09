import AppKit
import EventKit
import SwiftUI
import Observation

/// Un rappel à faire, tel qu'affiché dans l'encoche.
struct TodoItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let due: Date?
    /// Priorité EventKit : 0 = aucune, 1 = haute … 9 = basse.
    let priority: Int
    let listColor: Color
}

/// Logique pure : ordre d'affichage des rappels.
enum TodoOrdering {
    /// D'abord les rappels datés (le plus proche d'abord), puis les prioritaires, puis le reste par titre.
    static func sorted(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?) where x != y: return x < y
            case (.some, .none): return true
            case (.none, .some): return false
            default: break
            }
            let pa = a.priority == 0 ? 10 : a.priority
            let pb = b.priority == 0 ? 10 : b.priority
            if pa != pb { return pa < pb }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    static func isOverdue(_ item: TodoItem, now: Date = Date()) -> Bool {
        item.due.map { $0 < now } ?? false
    }
}

/// Module Todo : les rappels de l'app Rappels (EventKit), à cocher ou ajouter depuis l'encoche.
@MainActor
@Observable
final class TodoModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "todo",
        name: "Rappels",
        summary: "Vos rappels à faire, à cocher ou ajouter depuis l'encoche.",
        systemImage: "checklist",
        category: .productivity,
        tier: .free,
        defaultEnabled: false
    )

    static let maxItems = 30

    private(set) var authorization = EKEventStore.authorizationStatus(for: .reminder)
    private(set) var items: [TodoItem] = []

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(context: ModuleContext) {
        self.context = context
    }

    func start() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    // MARK: Accès

    func requestAccess() {
        guard !AutomatedRun.isActive else { return }
        store.requestFullAccessToReminders { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.authorization = EKEventStore.authorizationStatus(for: .reminder)
                    self?.refresh()
                }
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Rappels

    func refresh() {
        authorization = EKEventStore.authorizationStatus(for: .reminder)
        guard authorization == .fullAccess else { items = []; return }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let fetched = (reminders ?? []).map { reminder in
                TodoItem(
                    id: reminder.calendarItemIdentifier,
                    title: reminder.title ?? "",
                    due: reminder.dueDateComponents?.date,
                    priority: reminder.priority,
                    listColor: reminder.calendar.map { Color(cgColor: $0.cgColor) } ?? .orange
                )
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let sorted = Array(TodoOrdering.sorted(fetched).prefix(Self.maxItems))
                    guard let self, sorted != self.items else { return }
                    withAnimation(.snappy) { self.items = sorted }
                }
            }
        }
    }

    /// Coche un rappel (il disparaît de la liste).
    func complete(_ item: TodoItem) {
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
        withAnimation(.snappy) { items.removeAll { $0.id == item.id } }
    }

    /// Ajoute un rappel dans la liste par défaut de l'app Rappels.
    func add(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let calendar = store.defaultCalendarForNewReminders() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.calendar = calendar
        try? store.save(reminder, commit: true)
        refresh()
    }

    func openReminders() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func holdExpanded(_ hold: Bool) { context.holdExpanded(hold) }

    // MARK: Affichage

    var compactPriority: ModulePriority { .none }
    var expandedWidthWeight: CGFloat { 2 }

    func miniView() -> AnyView {
        AnyView(MiniWidget(symbol: "checklist", value: authorization == .fullAccess ? "\(items.count)" : nil,
                           caption: String(localized: "Rappels")))
    }

    func expandedView() -> AnyView {
        AnyView(TodoExpandedView(module: self))
    }
}
