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
    /// Transcription de la session (fichier JSONL), d'où sont lus les messages texte.
    let transcriptPath: String?
    /// Modification de fichier proposée (PreToolUse de Edit, MultiEdit ou Write), en extraits courts.
    let edit: ClaudeEdit?
    /// Commande exécutée et fin de sa sortie (PostToolUse de Bash).
    let command: ClaudeCommand?

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
        transcriptPath = json["transcript_path"] as? String

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

        let input = json["tool_input"] as? [String: Any] ?? [:]
        edit = name == "PreToolUse" ? toolName.flatMap { ClaudeEdit(toolName: $0, input: input) } : nil
        if name == "PostToolUse", toolName == "Bash", let command = input["command"] as? String {
            let response = json["tool_response"] as? [String: Any] ?? [:]
            let output = [response["stdout"] as? String, response["stderr"] as? String]
                .compactMap { $0 }.joined(separator: "\n")
            self.command = ClaudeCommand(command: command, output: output)
        } else {
            self.command = nil
        }
    }
}

/// Modification de fichier, réduite à quelques lignes pour l'affichage (jamais enregistrée sur disque).
struct ClaudeEdit: Equatable, Sendable {
    static let maxLines = 12
    static let maxLineLength = 160

    let filePath: String
    let removed: [String]
    let added: [String]
    /// Numéro (à partir de 1) de la première ligne modifiée, retrouvé dans le fichier quand c'est possible.
    var firstLine: Int?
    var isNewFile = false

    var fileName: String { URL(fileURLWithPath: filePath).lastPathComponent }

    init(filePath: String, removed: [String], added: [String], firstLine: Int? = nil, isNewFile: Bool = false) {
        self.filePath = filePath
        self.removed = removed
        self.added = added
        self.firstLine = firstLine
        self.isNewFile = isNewFile
    }

    /// Lit `tool_input` d'un outil de modification. `nil` pour les autres outils.
    init?(toolName: String, input: [String: Any], fileContents: (String) -> String? = ClaudeEdit.readSmallFile) {
        guard let path = (input["file_path"] ?? input["notebook_path"]) as? String else { return nil }
        let old: String
        let new: String
        switch toolName {
        case "Edit":
            old = input["old_string"] as? String ?? ""
            new = input["new_string"] as? String ?? ""
        case "MultiEdit":
            let first = (input["edits"] as? [[String: Any]])?.first
            old = first?["old_string"] as? String ?? ""
            new = first?["new_string"] as? String ?? ""
        case "Write":
            old = ""
            new = input["content"] as? String ?? ""
            isNewFile = true
        default:
            return nil
        }
        filePath = path
        removed = Self.lines(old)
        added = Self.lines(new)
        if !old.isEmpty, let contents = fileContents(path) {
            firstLine = Self.lineNumber(of: old, in: contents)
        } else if toolName == "Write" {
            firstLine = 1
        }
    }

    /// Découpe un texte en lignes courtes (pas plus de `maxLines`).
    static func lines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(maxLines)
            .map { String($0.prefix(maxLineLength)) }
    }

    /// Numéro de ligne (à partir de 1) où commence `snippet` dans `contents`.
    static func lineNumber(of snippet: String, in contents: String) -> Int? {
        guard let range = contents.range(of: snippet) else { return nil }
        return contents[..<range.lowerBound].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    /// Contenu d'un fichier texte local de taille raisonnable (sinon `nil`).
    static func readSmallFile(_ path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 2_000_000 else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// Commande lancée par Claude et dernières lignes de sa sortie.
struct ClaudeCommand: Equatable, Sendable {
    static let maxOutputLines = 6

    let command: String
    let output: [String]

    init(command: String, output: String) {
        self.command = String(command.prefix(200))
        self.output = output.split(separator: "\n").suffix(Self.maxOutputLines).map { String($0.prefix(160)) }
    }
}

/// Grandes étapes du travail d'un agent, affichées comme une liste à cocher.
enum ClaudePhase: CaseIterable, Sendable {
    case read, edit, run

    static func of(toolName: String) -> ClaudePhase? {
        switch toolName {
        case "Read", "Grep", "Glob", "WebFetch", "WebSearch", "LS": .read
        case "Edit", "MultiEdit", "Write", "NotebookEdit": .edit
        case "Bash": .run
        default: nil
        }
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
        /// Claude a terminé mais attend encore une éventuelle réponse depuis l'encoche.
        case awaitingReply
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
    /// Messages texte échangés (demandes et réponses de Claude), du plus ancien au plus récent.
    var conversation: [ClaudeChatEntry] = []
    var transcriptPath: String?
    /// Fin de la fenêtre de réponse (état `awaitingReply`).
    var replyDeadline: Date?
    var lastEventAt: Date
    /// Dernière modification de fichier et dernière commande, avec leur date (pour choisir laquelle montrer).
    var lastEdit: ClaudeEdit?
    var lastEditAt: Date?
    var lastCommand: ClaudeCommand?
    var lastCommandAt: Date?
    /// Étapes déjà franchies pour la demande en cours, et étape en cours.
    var phases: Set<ClaudePhase> = []
    var currentPhase: ClaudePhase?
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
        if let path = event.transcriptPath { session.transcriptPath = path }
        session.lastEventAt = date
        var transition: ClaudeTransition?

        switch event.kind {
        case .userPromptSubmit:
            session.state = .working
            session.replyDeadline = nil
            session.prompt = event.prompt.map { String($0.prefix(300)) }
            session.currentAction = nil
            session.recentActions = []
            session.attentionMessage = nil
            session.phases = []
            session.currentPhase = nil

        case .preToolUse:
            session.state = .working
            session.attentionMessage = nil
            if let tool = event.toolName {
                let (symbol, text) = ClaudeToolDescriber.describe(toolName: tool, summary: event.toolSummary)
                let action = ClaudeAction(symbol: symbol, text: text, date: date)
                session.currentAction = action
                session.recentActions.insert(action, at: 0)
                session.recentActions = Array(session.recentActions.prefix(Self.maxRecentActions))
                if let phase = ClaudePhase.of(toolName: tool) {
                    session.phases.insert(phase)
                    session.currentPhase = phase
                }
            }
            if let edit = event.edit {
                session.lastEdit = edit
                session.lastEditAt = date
            }

        case .postToolUse:
            session.state = .working
            session.attentionMessage = nil
            if let command = event.command {
                session.lastCommand = command
                session.lastCommandAt = date
            }

        case .stop:
            if session.state != .finished && session.state != .awaitingReply { transition = .finished }
            session.state = .finished
            session.replyDeadline = nil
            session.currentAction = nil
            session.attentionMessage = nil
            session.currentPhase = nil

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

    /// Nombre maximal de messages gardés par session (historique de l'encoche).
    static let maxConversation = 200

    /// Ajoute des messages lus dans la transcription (sans doublons).
    mutating func appendConversation(_ entries: [ClaudeChatEntry], to sessionID: String) {
        guard !entries.isEmpty, var session = sessions[sessionID] else { return }
        let known = Set(session.conversation.map(\.id))
        let fresh = entries.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return }
        session.conversation = Array((session.conversation + fresh).suffix(Self.maxConversation))
        sessions[sessionID] = session
    }

    /// Ouvre (avec une date de fin) ou ferme (`nil`) la fenêtre de réponse d'une session terminée.
    mutating func setReplyDeadline(_ deadline: Date?, for sessionID: String) {
        guard var session = sessions[sessionID] else { return }
        if let deadline {
            session.state = .awaitingReply
            session.replyDeadline = deadline
        } else {
            if session.state == .awaitingReply { session.state = .finished }
            session.replyDeadline = nil
        }
        sessions[sessionID] = session
    }

    /// Remet une session « au travail » (ex. après qu'un message l'a relancée).
    mutating func markWorking(_ sessionID: String, at date: Date = Date()) {
        guard var session = sessions[sessionID] else { return }
        session.state = .working
        session.replyDeadline = nil
        session.lastEventAt = date
        sessions[sessionID] = session
    }

    /// Passe en « terminée » les sessions sans nouvelles depuis trop longtemps.
    mutating func expireStaleSessions(at date: Date = Date()) {
        for (id, session) in sessions where (session.state == .working || session.state == .waitingForPermission)
            && date.timeIntervalSince(session.lastEventAt) > Self.staleInterval {
            sessions[id]?.state = .finished
            sessions[id]?.currentAction = nil
        }
    }

    var hasActiveSession: Bool {
        sessions.values.contains { $0.state == .working || $0.state == .waitingForPermission }
    }
}
