import Foundation

/// Événement envoyé par un hook de Claude Code (voir la documentation officielle des hooks).
struct ClaudeHookEvent: Sendable {
    enum Kind: Sendable, Equatable {
        case userPromptSubmit
        case preToolUse
        case postToolUse
        case stop
        case notification
        case sessionEnd
        case other(String)
    }

    let kind: Kind
    let sessionID: String
    let cwd: String?
    let toolName: String?
    /// Quelques champs utiles de `tool_input` (chemin, commande, motif…), déjà réduits en texte.
    let toolSummary: [String: String]
    let prompt: String?
    let notificationType: String?
    let message: String?

    /// Lit le JSON reçu sur l'entrée du hook. Renvoie `nil` s'il manque l'essentiel.
    init?(json: [String: Any]) {
        guard let name = json["hook_event_name"] as? String,
              let session = json["session_id"] as? String
        else { return nil }

        kind = switch name {
        case "UserPromptSubmit": .userPromptSubmit
        case "PreToolUse": .preToolUse
        case "PostToolUse": .postToolUse
        case "Stop": .stop
        case "Notification": .notification
        case "SessionEnd": .sessionEnd
        default: .other(name)
        }
        sessionID = session
        cwd = json["cwd"] as? String
        toolName = json["tool_name"] as? String
        prompt = json["prompt"] as? String
        notificationType = json["notification_type"] as? String
        message = json["message"] as? String

        // On ne garde que de courts extraits : jamais le contenu complet des fichiers écrits.
        var summary: [String: String] = [:]
        if let input = json["tool_input"] as? [String: Any] {
            for key in ["file_path", "notebook_path", "path", "command", "description", "pattern", "query", "url", "subagent_type", "prompt"] {
                if let value = input[key] as? String, !value.isEmpty {
                    summary[key] = String(value.prefix(200))
                }
            }
        }
        toolSummary = summary
    }
}

/// Action de Claude, telle qu'affichée dans l'encoche.
struct ClaudeAction: Identifiable, Equatable, Sendable {
    let id = UUID()
    let symbol: String
    let text: String
    let date: Date

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.symbol == rhs.symbol && lhs.text == rhs.text && lhs.date == rhs.date
    }
}

/// Traduit un appel d'outil en phrase courte et en icône.
enum ClaudeToolDescriber {
    static func describe(toolName: String, summary: [String: String]) -> (symbol: String, text: String) {
        let file = (summary["file_path"] ?? summary["notebook_path"] ?? summary["path"])
            .map { URL(fileURLWithPath: $0).lastPathComponent }

        switch toolName {
        case "Edit", "MultiEdit", "NotebookEdit":
            return ("pencil", String(localized: "Modifie \(file ?? "un fichier")"))
        case "Write":
            return ("doc.badge.plus", String(localized: "Écrit \(file ?? "un fichier")"))
        case "Read":
            return ("doc.text.magnifyingglass", String(localized: "Lit \(file ?? "un fichier")"))
        case "Bash":
            let what = summary["description"] ?? summary["command"].map { String($0.prefix(60)) } ?? ""
            return ("terminal", String(localized: "Exécute : \(what)"))
        case "Grep", "Glob":
            return ("magnifyingglass", String(localized: "Recherche « \(summary["pattern"] ?? "…") »"))
        case "WebFetch":
            let host = summary["url"].flatMap { URL(string: $0)?.host() } ?? "le web"
            return ("globe", String(localized: "Consulte \(host)"))
        case "WebSearch":
            return ("globe", String(localized: "Cherche sur le web « \(summary["query"] ?? "…") »"))
        case "Task", "Agent":
            return ("person.2", String(localized: "Lance un agent"))
        case "TodoWrite":
            return ("checklist", String(localized: "Met à jour sa liste de tâches"))
        default:
            if toolName.hasPrefix("mcp__") {
                let server = toolName.split(separator: "_", omittingEmptySubsequences: true).dropFirst().first.map(String.init) ?? toolName
                return ("puzzlepiece.extension", String(localized: "Utilise \(server)"))
            }
            return ("wrench.and.screwdriver", String(localized: "Utilise \(toolName)"))
        }
    }
}

/// Session de Claude Code suivie par Notchkit.
struct ClaudeSession: Identifiable, Equatable, Sendable {
    enum State: Sendable, Equatable {
        case working
        case waitingForPermission
        case finished
    }

    let id: String
    var projectName: String?
    var state: State
    var prompt: String?
    var currentAction: ClaudeAction?
    /// Dernières actions, de la plus récente à la plus ancienne.
    var recentActions: [ClaudeAction] = []
    /// Message affiché par Claude Code quand il demande une permission.
    var attentionMessage: String?
    var lastEventAt: Date
}

/// Ce qui vient de changer, pour déclencher une alerte.
enum ClaudeTransition: Equatable, Sendable {
    case finished
    case needsPermission
}

/// Suivi des sessions à partir des événements des hooks (logique pure, testable).
struct ClaudeActivityTracker: Equatable, Sendable {
    /// Au-delà, une session « au travail » sans nouvelles est considérée comme terminée
    /// (ex. interrompue avec Échap, qui ne déclenche pas de hook Stop).
    static let staleInterval: TimeInterval = 10 * 60
    static let maxRecentActions = 5

    private(set) var sessions: [String: ClaudeSession] = [:]

    /// Session la plus récemment active.
    var displayedSession: ClaudeSession? {
        sessions.values.max { $0.lastEventAt < $1.lastEventAt }
    }

    @discardableResult
    mutating func apply(_ event: ClaudeHookEvent, at date: Date = Date()) -> ClaudeTransition? {
        if event.kind == .sessionEnd {
            sessions.removeValue(forKey: event.sessionID)
            return nil
        }

        var session = sessions[event.sessionID] ?? ClaudeSession(id: event.sessionID, state: .finished, lastEventAt: date)
        if let cwd = event.cwd { session.projectName = URL(fileURLWithPath: cwd).lastPathComponent }
        session.lastEventAt = date
        var transition: ClaudeTransition?

        switch event.kind {
        case .userPromptSubmit:
            session.state = .working
            session.prompt = event.prompt.map { String($0.prefix(300)) }
            session.currentAction = nil
            session.recentActions = []
            session.attentionMessage = nil

        case .preToolUse:
            session.state = .working
            session.attentionMessage = nil
            if let tool = event.toolName {
                let (symbol, text) = ClaudeToolDescriber.describe(toolName: tool, summary: event.toolSummary)
                let action = ClaudeAction(symbol: symbol, text: text, date: date)
                session.currentAction = action
                session.recentActions.insert(action, at: 0)
                session.recentActions = Array(session.recentActions.prefix(Self.maxRecentActions))
            }

        case .postToolUse:
            session.state = .working
            session.attentionMessage = nil

        case .stop:
            if session.state != .finished { transition = .finished }
            session.state = .finished
            session.currentAction = nil
            session.attentionMessage = nil

        case .notification:
            if event.notificationType == "permission_prompt" {
                if session.state != .waitingForPermission { transition = .needsPermission }
                session.state = .waitingForPermission
                session.attentionMessage = event.message
            }

        case .sessionEnd, .other:
            break
        }

        sessions[event.sessionID] = session
        return transition
    }

    /// Passe en « terminée » les sessions sans nouvelles depuis trop longtemps.
    mutating func expireStaleSessions(at date: Date = Date()) {
        for (id, session) in sessions where session.state != .finished
            && date.timeIntervalSince(session.lastEventAt) > Self.staleInterval {
            sessions[id]?.state = .finished
            sessions[id]?.currentAction = nil
        }
    }

    var hasActiveSession: Bool {
        sessions.values.contains { $0.state != .finished }
    }
}
