import AppKit
import SwiftUI
import Observation

/// Module Claude Code : activité en direct, messages envoyés depuis l'encoche et utilisation estimée.
///
/// Repose sur les hooks officiels de Claude Code (type « http ») : Claude Code prévient Notchkit
/// à chaque événement, et nos réponses peuvent lui transmettre un message de l'utilisateur :
/// - pendant qu'il travaille : à sa prochaine action (`additionalContext` de PostToolUse) ;
/// - quand il s'apprête à s'arrêter : le hook Stop le fait continuer avec le message ;
/// - s'il est déjà à l'arrêt : avec la prochaine demande faite dans Claude Code
///   (aucun hook ne peut relancer une session inactive, d'après la documentation).
@MainActor
@Observable
final class ClaudeModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "claude",
        name: "Claude Code",
        summary: "Activité de Claude Code en direct, messages depuis l'encoche et utilisation estimée.",
        systemImage: "sparkle",
        category: .productivity,
        tier: .free,
        defaultEnabled: true
    )

    static let defaultPort: UInt16 = 52_731

    private(set) var tracker = ClaudeActivityTracker()
    private(set) var serverState: ClaudeHookServer.State = .stopped
    private(set) var hooksInstalled = false
    private(set) var installerMessage: String?
    private(set) var usage: ClaudeUsageSummary?
    /// Messages en attente de remise, par session.
    private(set) var pendingMessages: [String: [String]] = [:]

    // MARK: Réglages du module

    var showInCompact: Bool {
        didSet { UserDefaults.standard.set(showInCompact, forKey: Keys.showInCompact) }
    }
    var alertOnFinish: Bool {
        didSet { UserDefaults.standard.set(alertOnFinish, forKey: Keys.alertOnFinish) }
    }

    private enum Keys {
        static let showInCompact = "module.claude.showInCompact"
        static let alertOnFinish = "module.claude.alertOnFinish"
        static let token = "module.claude.token"
        static let port = "module.claude.port"
        static let personalMax = "module.claude.personalMaxTokens"
    }

    let port: UInt16
    @ObservationIgnored private let token: String
    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private let server: ClaudeHookServer
    @ObservationIgnored private var maintenanceTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false

    init(context: ModuleContext) {
        self.context = context
        let defaults = UserDefaults.standard
        showInCompact = defaults.object(forKey: Keys.showInCompact) as? Bool ?? true
        alertOnFinish = defaults.object(forKey: Keys.alertOnFinish) as? Bool ?? true

        // Jeton secret propre à ce Mac, partagé uniquement avec la configuration des hooks.
        if let stored = defaults.string(forKey: Keys.token) {
            token = stored
        } else {
            let generated = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
            defaults.set(generated, forKey: Keys.token)
            token = generated
        }
        let storedPort = defaults.integer(forKey: Keys.port)
        port = (1024...65535).contains(storedPort) ? UInt16(storedPort) : Self.defaultPort
        server = ClaudeHookServer(token: token)
    }

    // MARK: Cycle de vie

    func start() {
        guard !isStarted else { return }
        isStarted = true

        server.onStateChange = { [weak self] state in self?.serverState = state }
        server.handler = { [weak self] json in self?.handle(json) }
        server.start(port: port)
        refreshInstallState()

        // Toutes les minutes : sessions interrompues sans hook Stop, et toutes les 10 minutes : utilisation.
        maintenanceTask = Task { [weak self] in
            var minute = 0
            while !Task.isCancelled {
                if minute.isMultiple(of: 10) { await self?.refreshUsage() }
                try? await Task.sleep(for: .seconds(60))
                self?.tracker.expireStaleSessions()
                minute += 1
            }
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        maintenanceTask?.cancel()
        maintenanceTask = nil
        server.stop()
    }

    // MARK: Hooks

    /// Traite un événement reçu et renvoie, si besoin, la réponse destinée à Claude Code.
    func handle(_ json: [String: Any]) -> [String: Any]? {
        guard let event = ClaudeHookEvent(json: json) else { return nil }
        let transition = tracker.apply(event)

        switch transition {
        case .finished:
            if alertOnFinish && pendingMessages[event.sessionID]?.isEmpty != false {
                context.presentAlert(ClaudeAlerts.finished())
            }
            Task { await refreshUsage() }
        case .needsPermission, nil:
            break
        }

        return deliverPendingMessage(for: event)
    }

    /// Remet le message en attente à Claude au moment opportun.
    private func deliverPendingMessage(for event: ClaudeHookEvent) -> [String: Any]? {
        guard var queue = pendingMessages[event.sessionID], !queue.isEmpty else { return nil }
        let text = queue.joined(separator: "\n\n")
        let message = "Message de l'utilisateur, envoyé depuis l'encoche Notchkit : \(text)"

        let response: [String: Any]
        switch event.kind {
        case .stop:
            // Claude allait s'arrêter : il continue en tenant compte du message.
            response = ["decision": "block", "reason": message]
            tracker.apply(Self.syntheticWorkingEvent(sessionID: event.sessionID))
        case .postToolUse, .userPromptSubmit:
            let name = event.kind == .postToolUse ? "PostToolUse" : "UserPromptSubmit"
            response = ["hookSpecificOutput": ["hookEventName": name, "additionalContext": message]]
        default:
            return nil
        }
        queue.removeAll()
        pendingMessages[event.sessionID] = nil
        return response
    }

    /// Après un Stop bloqué, la session reprend : on la remet « au travail ».
    private static func syntheticWorkingEvent(sessionID: String) -> ClaudeHookEvent {
        ClaudeHookEvent(json: ["hook_event_name": "PostToolUse", "session_id": sessionID])!
    }

    // MARK: Messages

    var displayedSession: ClaudeSession? { tracker.displayedSession }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let session = displayedSession else { return }
        pendingMessages[session.id, default: []].append(trimmed)
    }

    func holdExpanded(_ hold: Bool) {
        context.holdExpanded(hold)
    }

    func openSettings() {
        context.openSettings()
    }

    // MARK: Installation

    func refreshInstallState() {
        hooksInstalled = ClaudeHooksInstaller.isInstalled(port: port, token: token)
    }

    func installHooks() {
        do {
            let backup = try ClaudeHooksInstaller.install(port: port, token: token)
            installerMessage = backup.map { String(localized: "Intégration installée. Sauvegarde de vos réglages : \($0.lastPathComponent)") }
                ?? String(localized: "Intégration installée.")
        } catch {
            installerMessage = error.localizedDescription
        }
        refreshInstallState()
    }

    func uninstallHooks() {
        do {
            try ClaudeHooksInstaller.uninstall()
            installerMessage = String(localized: "Intégration retirée.")
        } catch {
            installerMessage = error.localizedDescription
        }
        refreshInstallState()
    }

    // MARK: Utilisation

    private func refreshUsage() async {
        let defaults = UserDefaults.standard
        let storedMax = defaults.integer(forKey: Keys.personalMax)
        // Au premier calcul, on remonte 7 jours pour trouver un repère ; ensuite 10 h suffisent.
        let lookback: TimeInterval = storedMax == 0 ? 7 * 86_400 : 10 * 3600
        let entries = await ClaudeUsageLoader.entries(since: Date().addingTimeInterval(-lookback))
        let summary = ClaudeUsageCalculator.summary(from: entries, storedMax: storedMax)
        if summary.personalMax > storedMax { defaults.set(summary.personalMax, forKey: Keys.personalMax) }
        if summary != usage { usage = summary }
    }

    // MARK: Affichage

    var compactPriority: ModulePriority {
        guard showInCompact, let session = displayedSession else { return .none }
        switch session.state {
        case .waitingForPermission: return .high
        case .working: return .elevated
        case .finished: return .none
        }
    }

    var expandedWidthWeight: CGFloat { 2 }

    func compactLeading() -> AnyView? {
        guard let session = displayedSession, session.state != .finished else { return nil }
        return AnyView(
            ClaudeSparkView(isAnimating: session.state == .working)
                .frame(width: 18, height: 18)
        )
    }

    func compactTrailing() -> AnyView? {
        guard let session = displayedSession else { return nil }
        switch session.state {
        case .waitingForPermission:
            return AnyView(
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(Color(nsColor: ClaudeSparkView.color))
            )
        case .working:
            return AnyView(
                Image(systemName: session.currentAction?.symbol ?? "ellipsis")
                    .foregroundStyle(.white.opacity(0.85))
                    .contentTransition(.symbolEffect(.replace))
            )
        case .finished:
            return nil
        }
    }

    func expandedView() -> AnyView {
        AnyView(ClaudeExpandedView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(ClaudeSettingsView(module: self))
    }
}

enum ClaudeAlerts {
    @MainActor
    static func finished() -> NotchAlert {
        NotchAlert(
            leading: AnyView(ClaudeSparkView(isAnimating: false).frame(width: 18, height: 18)),
            trailing: AnyView(
                Label("Terminé", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
            ),
            duration: .seconds(3)
        )
    }
}
