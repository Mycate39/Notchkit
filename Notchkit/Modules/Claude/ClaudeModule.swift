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
        systemImage: ClaudeMark.symbolName,
        category: .productivity,
        tier: .free,
        defaultEnabled: true
    )

    static let defaultPort: UInt16 = 52_731

    private(set) var tracker = ClaudeActivityTracker()
    private(set) var serverState: ClaudeHookServer.State = .stopped
    private(set) var installStatus: ClaudeHooksInstaller.Status = .notInstalled
    var hooksInstalled: Bool { installStatus == .installed }
    private(set) var installerMessage: String?
    private(set) var usage: ClaudeUsageSummary?
    /// Utilisation réelle transmise par la barre d'état de Claude Code (prioritaire sur l'estimation).
    private(set) var rateLimits: ClaudeRateLimits?
    /// L'utilisateur a sa propre barre d'état : l'utilisation réelle n'est pas transmise.
    private(set) var hasCustomStatusLine = false
    /// Messages en attente de remise, par session.
    private(set) var pendingMessages: [String: [String]] = [:]

    // MARK: Réglages du module

    var showInCompact: Bool {
        didSet { UserDefaults.standard.set(showInCompact, forKey: Keys.showInCompact) }
    }
    var alertOnFinish: Bool {
        didSet { UserDefaults.standard.set(alertOnFinish, forKey: Keys.alertOnFinish) }
    }
    /// Durée (secondes) pendant laquelle on peut encore répondre depuis l'encoche après la fin
    /// d'une réponse de Claude. 0 = désactivé. Pendant ce délai, Claude Code reste « en cours ».
    var replyWindow: Int {
        didSet { UserDefaults.standard.set(replyWindow, forKey: Keys.replyWindow) }
    }
    static let replyWindowChoices = [0, 30, 60, 120, 240]

    private enum Keys {
        static let showInCompact = "module.claude.showInCompact"
        static let alertOnFinish = "module.claude.alertOnFinish"
        static let replyWindow = "module.claude.replyWindow"
        static let token = "module.claude.token"
        static let port = "module.claude.port"
        static let personalMax = "module.claude.personalMaxTokens"
        static let rateLimits = "module.claude.rateLimits"
    }

    let port: UInt16
    @ObservationIgnored private let token: String
    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private let server: ClaudeHookServer
    @ObservationIgnored private var maintenanceTask: Task<Void, Never>?
    /// Relecture régulière de la transcription tant que Claude travaille (messages en direct).
    @ObservationIgnored private var transcriptTask: Task<Void, Never>?
    @ObservationIgnored private let transcriptReader = ClaudeTranscriptReader()
    @ObservationIgnored private var isStarted = false
    /// Hooks Stop gardés ouverts (fenêtre de réponse), par session.
    @ObservationIgnored private var heldStops: [String: HookReply] = [:]
    @ObservationIgnored private var replyTimers: [String: Task<Void, Never>] = [:]

    init(context: ModuleContext) {
        self.context = context
        let defaults = UserDefaults.standard
        showInCompact = defaults.object(forKey: Keys.showInCompact) as? Bool ?? true
        alertOnFinish = defaults.object(forKey: Keys.alertOnFinish) as? Bool ?? true
        replyWindow = defaults.object(forKey: Keys.replyWindow) as? Int ?? 0

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
        // Dernière utilisation réelle connue (affichée dès le lancement).
        rateLimits = defaults.data(forKey: Keys.rateLimits)
            .flatMap { try? JSONDecoder().decode(ClaudeRateLimits.self, from: $0) }
            .map { $0.merged(with: nil) }
    }

    // MARK: Cycle de vie

    func start() {
        guard !isStarted else { return }
        isStarted = true

        server.onStateChange = { [weak self] state in self?.serverState = state }
        server.handler = { [weak self] json, reply in
            guard let self else { return reply.send(nil) }
            self.handle(json, reply: reply)
        }
        server.statusHandler = { [weak self] json in self?.handleStatus(json) ?? "" }
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
        transcriptTask?.cancel()
        transcriptTask = nil
        for id in Array(heldStops.keys) { closeReplyWindow(id, respond: true) }
        server.stop()
    }

    // MARK: Hooks

    /// Traite un événement reçu et répond à Claude Code (tout de suite, ou plus tard pour Stop).
    func handle(_ json: [String: Any], reply: HookReply) {
        guard let event = ClaudeHookEvent(json: json) else { return reply.send(nil) }
        let transition = tracker.apply(event)
        readTranscript(of: event.sessionID)
        updateTranscriptPolling()

        switch transition {
        case .finished:
            if alertOnFinish && pendingMessages[event.sessionID]?.isEmpty != false {
                context.presentAlert(ClaudeAlerts.finished())
            }
            Task { await refreshUsage() }
        case .needsPermission, nil:
            break
        }

        if let response = deliverPendingMessage(for: event) {
            return reply.send(response)
        }
        // Claude vient de terminer : on garde le hook ouvert pour qu'une réponse depuis
        // l'encoche puisse le relancer.
        if event.kind == .stop, replyWindow > 0 {
            return openReplyWindow(event.sessionID, reply: reply)
        }
        reply.send(nil)
    }

    // MARK: Messages en direct

    /// Lit les nouveaux messages de la transcription d'une session.
    private func readTranscript(of sessionID: String) {
        guard !AutomatedRun.isActive, let path = tracker.sessions[sessionID]?.transcriptPath else { return }
        let reader = transcriptReader
        Task { [weak self] in
            let entries = await reader.newEntries(at: path)
            self?.tracker.appendConversation(entries, to: sessionID)
        }
    }

    /// Tant qu'une session travaille, relit sa transcription toutes les 1,5 s : le texte de Claude
    /// apparaît sans attendre le prochain hook. S'arrête dès qu'il n'y a plus d'activité.
    private func updateTranscriptPolling() {
        guard tracker.hasActiveSession else {
            transcriptTask?.cancel()
            transcriptTask = nil
            return
        }
        guard transcriptTask == nil else { return }
        transcriptTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, !Task.isCancelled else { return }
                for session in self.tracker.sessions.values where session.state == .working || session.state == .waitingForPermission {
                    self.readTranscript(of: session.id)
                }
                if !self.tracker.hasActiveSession {
                    // Dernière lecture (réponse finale), puis arrêt.
                    self.tracker.sessions.keys.forEach(self.readTranscript(of:))
                    self.transcriptTask = nil
                    return
                }
            }
        }
    }

    /// Données de la barre d'état : on en extrait l'utilisation réelle et on renvoie la ligne à afficher.
    func handleStatus(_ json: [String: Any]) -> String {
        if let limits = ClaudeRateLimits(statusJSON: json) {
            let merged = limits.merged(with: rateLimits)
            if merged != rateLimits {
                rateLimits = merged
                UserDefaults.standard.set(try? JSONEncoder().encode(merged), forKey: Keys.rateLimits)
            }
        }
        return rateLimits?.statusLineText() ?? "Notchkit"
    }

    /// Variante synchrone (tests) : renvoie la réponse immédiate éventuelle.
    func handle(_ json: [String: Any]) -> [String: Any]? {
        var result: [String: Any]?
        handle(json, reply: HookReply { result = $0 })
        return result
    }

    /// Remet le message en attente à Claude au moment opportun.
    private func deliverPendingMessage(for event: ClaudeHookEvent) -> [String: Any]? {
        guard let queue = pendingMessages[event.sessionID], !queue.isEmpty else { return nil }
        let message = Self.formatted(queue)

        let response: [String: Any]
        switch event.kind {
        case .stop:
            // Claude allait s'arrêter : il continue en tenant compte du message.
            response = ["decision": "block", "reason": message]
            tracker.markWorking(event.sessionID)
        case .postToolUse, .userPromptSubmit:
            let name = event.kind == .postToolUse ? "PostToolUse" : "UserPromptSubmit"
            response = ["hookSpecificOutput": ["hookEventName": name, "additionalContext": message]]
        default:
            return nil
        }
        pendingMessages[event.sessionID] = nil
        return response
    }

    private static func formatted(_ messages: [String]) -> String {
        "Message from the user, sent from the Notchkit notch: \(messages.joined(separator: "\n\n"))"
    }

    // MARK: Fenêtre de réponse

    private func openReplyWindow(_ sessionID: String, reply: HookReply) {
        closeReplyWindow(sessionID, respond: true)
        let seconds = replyWindow
        heldStops[sessionID] = reply
        tracker.setReplyDeadline(Date().addingTimeInterval(TimeInterval(seconds)), for: sessionID)

        // Échap dans Claude Code : la requête est abandonnée, la fenêtre se ferme.
        reply.onClientClose = { [weak self] in self?.closeReplyWindow(sessionID, respond: false) }
        replyTimers[sessionID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.closeReplyWindow(sessionID, respond: true)
        }
    }

    /// Ferme la fenêtre : Claude Code reçoit une réponse vide et termine normalement.
    private func closeReplyWindow(_ sessionID: String, respond: Bool) {
        replyTimers.removeValue(forKey: sessionID)?.cancel()
        if let reply = heldStops.removeValue(forKey: sessionID), respond {
            reply.send(nil)
        }
        tracker.setReplyDeadline(nil, for: sessionID)
    }

    // MARK: Messages

    var displayedSession: ClaudeSession? { tracker.displayedSession }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let session = displayedSession else { return }

        // Fenêtre de réponse ouverte : Claude repart immédiatement avec le message.
        if let reply = heldStops.removeValue(forKey: session.id) {
            replyTimers.removeValue(forKey: session.id)?.cancel()
            reply.send(["decision": "block", "reason": Self.formatted([trimmed])])
            tracker.markWorking(session.id)
            return
        }
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
        installStatus = ClaudeHooksInstaller.status(port: port, token: token)
        hasCustomStatusLine = ClaudeHooksInstaller.hasCustomStatusLine()
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
        case .working, .awaitingReply: return .elevated
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
        case .awaitingReply:
            guard let deadline = session.replyDeadline else { return nil }
            // Temps restant pour répondre depuis l'encoche (fenêtre de réponse).
            return AnyView(
                HStack(spacing: 3) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(nsColor: ClaudeSparkView.color))
                    ReplyCountdown(deadline: deadline)
                }
                .help("Temps restant pour répondre à Claude depuis l'encoche")
            )
        case .finished:
            return nil
        }
    }

    func miniView() -> AnyView {
        let session = displayedSession
        let percent: String? = (rateLimits?.fiveHour?.fraction()).map { $0.formatted(.percent.precision(.fractionLength(0))) }
            ?? usage?.usedFraction.map { "≈ " + $0.formatted(.percent.precision(.fractionLength(0))) }
        let caption: String = switch session?.state {
        case .working: String(localized: "Au travail")
        case .waitingForPermission: String(localized: "Votre accord")
        case .awaitingReply: String(localized: "Terminé")
        default: String(localized: "Session")
        }
        return AnyView(
            MiniWidget(value: percent, caption: caption) {
                ClaudeSparkView(isAnimating: session?.state == .working).frame(width: 30, height: 30)
            }
        )
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

#if DEBUG
extension ClaudeModule {
    /// Session fictive pour les images de démonstration (rien n'est enregistré).
    func debugSetDemo(events: [ClaudeHookEvent], conversation: [ClaudeChatEntry] = []) {
        installStatus = .installed
        var demo = ClaudeActivityTracker()
        for event in events { _ = demo.apply(event) }
        if let sessionID = events.first?.sessionID, !conversation.isEmpty {
            demo.appendConversation(conversation, to: sessionID)
        }
        tracker = demo
    }
}
#endif
