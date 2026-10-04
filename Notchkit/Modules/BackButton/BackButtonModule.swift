import AppKit
import SwiftUI
import Observation

/// App mémorisée dans l'historique des changements d'app.
struct RecentApp: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let name: String
}

/// Historique des apps passées au premier plan (logique pure, testée).
struct AppSwitchHistory: Equatable, Sendable {
    static let ignoredBundleIDs: Set<String> = [
        "com.andeolchenaux.notchkit",
        "com.apple.SecurityAgent",
        "com.apple.LocalAuthentication.UIAgent",
        "com.apple.loginwindow",
    ]

    private(set) var apps: [RecentApp] = []

    /// Enregistre une app passée au premier plan. Renvoie vrai si l'app au premier plan a changé.
    @discardableResult
    mutating func activated(_ app: RecentApp) -> Bool {
        if let id = app.bundleIdentifier, Self.ignoredBundleIDs.contains(id) { return false }
        if apps.first?.processIdentifier == app.processIdentifier { return false }
        apps.removeAll { $0.processIdentifier == app.processIdentifier }
        apps.insert(app, at: 0)
        apps = Array(apps.prefix(10))
        return true
    }

    mutating func terminated(processIdentifier: pid_t) {
        apps.removeAll { $0.processIdentifier == processIdentifier }
    }

    /// App d'avant (celle vers laquelle revenir).
    var previous: RecentApp? { apps.dropFirst().first }
}

/// Module Retour : bouton « ◀ App » pour revenir à l'app précédente, comme sur iPhone.
@MainActor
@Observable
final class BackButtonModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "back",
        name: "Retour à l'app précédente",
        summary: "Bouton « ◀ App » pour revenir à l'app d'avant, comme sur iPhone.",
        systemImage: "chevron.backward.circle",
        category: .system,
        tier: .free,
        defaultEnabled: true
    )

    /// Durée d'affichage dans l'encoche repliée après un changement d'app (0 = toujours).
    static let displayChoices = [5, 8, 15, 0]

    private(set) var history = AppSwitchHistory()
    /// Vrai pendant quelques secondes après un changement d'app.
    private(set) var isRecentlySwitched = false

    var displaySeconds: Int {
        didSet { UserDefaults.standard.set(displaySeconds, forKey: Keys.displaySeconds) }
    }

    private enum Keys {
        static let displaySeconds = "module.back.displaySeconds"
    }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    init(context: ModuleContext) {
        self.context = context
        displaySeconds = UserDefaults.standard.object(forKey: Keys.displaySeconds) as? Int ?? 8
    }

    var previousApp: RecentApp? { history.previous }

    // MARK: Cycle de vie

    func start() {
        guard observers.isEmpty else { return }
        if let front = NSWorkspace.shared.frontmostApplication { history.activated(Self.recent(front)) }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let recent = Self.recent(app)
            MainActor.assumeIsolated { self?.appActivated(recent) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.history.terminated(processIdentifier: pid) }
        })
    }

    func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        hideTask?.cancel()
    }

    nonisolated private static func recent(_ app: NSRunningApplication) -> RecentApp {
        RecentApp(processIdentifier: app.processIdentifier, bundleIdentifier: app.bundleIdentifier,
                  name: app.localizedName ?? app.bundleIdentifier ?? "?")
    }

    private func appActivated(_ app: RecentApp) {
        guard history.activated(app), history.previous != nil else { return }
        withAnimation(.snappy) { isRecentlySwitched = true }
        hideTask?.cancel()
        guard displaySeconds > 0 else { return }
        let seconds = displaySeconds
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { self?.isRecentlySwitched = false }
        }
    }

    // MARK: Action

    /// Revient à l'app précédente.
    func goBack() {
        guard let previous = previousApp else { return }
        if let app = NSRunningApplication(processIdentifier: previous.processIdentifier), !app.isTerminated {
            app.activate()
        } else if let id = previous.bundleIdentifier,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Empêche l'encoche de s'ouvrir tant que la souris est sur le bouton (pour cliquer sans gêne).
    func blockExpansion(_ blocked: Bool) {
        context.blockExpansion(blocked)
    }

    // MARK: Affichage

    var compactPriority: ModulePriority {
        guard previousApp != nil else { return .none }
        if displaySeconds == 0 { return .low }
        return isRecentlySwitched ? .elevated : .none
    }

    var expandedWidthWeight: CGFloat { 1 }

    func compactLeading() -> AnyView? {
        guard let previous = previousApp else { return nil }
        return AnyView(BackLink(name: previous.name, action: goBack, onHover: blockExpansion))
    }

    func compactTrailing() -> AnyView? {
        guard let id = previousApp?.bundleIdentifier, let icon = AppIconCache.icon(for: id) else { return nil }
        return AnyView(Image(nsImage: icon).resizable().frame(width: 16, height: 16))
    }

    func miniView() -> AnyView {
        AnyView(BackMiniView(module: self))
    }

    func expandedView() -> AnyView {
        AnyView(BackMiniView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(BackButtonSettingsView(module: self))
    }
}

// MARK: - Vues

/// Lien « ◀ App », façon barre d'état d'iOS.
struct BackLink: View {
    let name: String
    let action: () -> Void
    var onHover: (Bool) -> Void = { _ in }
    var fontSize: CGFloat = 11

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: fontSize - 1, weight: .bold))
                Text(name)
                    .font(.system(size: fontSize, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(.tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .help("Revenir à \(name)")
    }
}

private struct BackMiniView: View {
    let module: BackButtonModule

    var body: some View {
        if let previous = module.previousApp {
            Button(action: module.goBack) {
                VStack(spacing: 6) {
                    if let id = previous.bundleIdentifier, let icon = AppIconCache.icon(for: id) {
                        Image(nsImage: icon).resizable().frame(width: 34, height: 34)
                    }
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.backward").font(.system(size: 9, weight: .bold))
                        Text(previous.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    }
                    .foregroundStyle(.tint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            MiniWidget(symbol: "chevron.backward.circle", value: nil, caption: String(localized: "Aucune app"))
        }
    }
}

struct BackButtonSettingsView: View {
    @Bindable var module: BackButtonModule

    var body: some View {
        Picker("Afficher dans l'encoche repliée", selection: $module.displaySeconds) {
            ForEach(BackButtonModule.displayChoices, id: \.self) { seconds in
                if seconds == 0 { Text("Toujours").tag(seconds) } else { Text("\(seconds) s après un changement d'app").tag(seconds) }
            }
        }
    }
}
