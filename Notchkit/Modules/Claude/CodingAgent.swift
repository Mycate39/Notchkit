import Foundation

/// Agent de code suivi par la page Agents. Claude Code parle à Notchkit par ses hooks HTTP ; les autres
/// par des hooks « commande » qui relaient leur JSON au même serveur local (`agent-hook.sh`).
enum CodingAgent: String, CaseIterable, Identifiable, Sendable {
    case claude, codex, gemini, cursor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini CLI"
        case .cursor: "Cursor"
        }
    }

    /// Notchkit peut accorder ou refuser une autorisation à sa place (Claude Code et Codex).
    var answersPermissions: Bool { self == .claude || self == .codex }

    /// Agents installés par `AgentHooksInstaller` (Claude Code a son propre installateur).
    static var bridged: [CodingAgent] { [.codex, .gemini, .cursor] }

    /// Dossier de configuration de l'agent : sa présence indique qu'il est installé sur ce Mac.
    var configDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return switch self {
        case .claude: home.appendingPathComponent(".claude", isDirectory: true)
        case .codex: home.appendingPathComponent(".codex", isDirectory: true)
        case .gemini: home.appendingPathComponent(".gemini", isDirectory: true)
        case .cursor: home.appendingPathComponent(".cursor", isDirectory: true)
        }
    }

    /// Fichier où sont écrits les hooks.
    var hooksFile: URL {
        switch self {
        case .claude, .gemini: configDirectory.appendingPathComponent("settings.json")
        case .codex, .cursor: configDirectory.appendingPathComponent("hooks.json")
        }
    }

    /// Identifiant de session interne : préfixé, pour que deux agents ne partagent jamais une session.
    func sessionID(_ raw: String) -> String {
        self == .claude ? raw : "\(rawValue):\(raw)"
    }

    /// Agent d'une session, d'après son identifiant interne.
    static func of(sessionID: String) -> CodingAgent {
        bridged.first { sessionID.hasPrefix("\($0.rawValue):") } ?? .claude
    }
}

/// Traduit les hooks de Codex, Gemini CLI et Cursor vers les événements de Claude Code (déjà compris
/// par le suivi des sessions), puis les réponses de Notchkit vers le format de chaque agent.
/// Logique pure, testée.
enum AgentHookTranslator {
    static let path = "/notchkit/agent/hook"

    // MARK: Événements reçus

    /// Événements au format de Claude Code. Un hook peut en donner plusieurs (Cursor : commande lancée
    /// puis sa sortie), ou aucun (événement ignoré).
    static func events(from json: [String: Any], agent: CodingAgent) -> [[String: Any]] {
        switch agent {
        case .claude: [json]
        case .codex: codex(json)
        case .gemini: gemini(json)
        case .cursor: cursor(json)
        }
    }

    /// Codex suit déjà les noms et les champs de Claude Code ; seuls ses outils diffèrent.
    private static func codex(_ json: [String: Any]) -> [[String: Any]] {
        guard let name = json["hook_event_name"] as? String, let session = json["session_id"] as? String else { return [] }
        var event = base(name: name, session: CodingAgent.codex.sessionID(session), cwd: json["cwd"] as? String)
        event["prompt"] = json["prompt"]
        if let tool = json["tool_name"] as? String {
            let input = json["tool_input"] as? [String: Any] ?? [:]
            if tool == "apply_patch", let patch = input["command"] as? String {
                let (mapped, mappedInput) = patchEdit(patch)
                event["tool_name"] = mapped
                event["tool_input"] = mappedInput
            } else {
                event["tool_name"] = tool
                event["tool_input"] = input
            }
            event["tool_response"] = shellResponse(json["tool_response"])
        }
        return [event]
    }

    private static func gemini(_ json: [String: Any]) -> [[String: Any]] {
        guard let name = json["hook_event_name"] as? String, let session = json["session_id"] as? String else { return [] }
        let claudeName: String
        switch name {
        case "BeforeAgent": claudeName = "UserPromptSubmit"
        case "BeforeTool": claudeName = "PreToolUse"
        case "AfterTool": claudeName = "PostToolUse"
        case "AfterAgent": claudeName = "Stop"
        case "SessionEnd": claudeName = "SessionEnd"
        case "Notification": claudeName = "Notification"
        default: return []
        }
        var event = base(name: claudeName, session: CodingAgent.gemini.sessionID(session), cwd: json["cwd"] as? String)
        event["prompt"] = json["prompt"]
        if name == "Notification" {
            // Seule notification documentée : une demande d'accord, à donner dans le terminal.
            guard json["notification_type"] as? String == "ToolPermission" else { return [] }
            event["notification_type"] = "permission_prompt"
            event["message"] = json["message"]
        }
        if let tool = json["tool_name"] as? String {
            let input = json["tool_input"] as? [String: Any] ?? [:]
            let (mapped, mappedInput) = geminiTool(tool, input: input)
            event["tool_name"] = mapped
            event["tool_input"] = mappedInput
            if let response = json["tool_response"] as? [String: Any] {
                let text = (response["returnDisplay"] as? String) ?? (response["llmContent"] as? String) ?? ""
                event["tool_response"] = ["stdout": text]
            }
        }
        return [event]
    }

    private static func geminiTool(_ tool: String, input: [String: Any]) -> (String, [String: Any]) {
        switch tool {
        case "run_shell_command":
            return ("Bash", ["command": input["command"] ?? "", "description": input["description"] ?? ""])
        case "write_file": return ("Write", input)
        case "replace": return ("Edit", input)
        case "read_file", "read_many_files": return ("Read", input)
        case "web_fetch": return ("WebFetch", ["url": firstURL(in: input["prompt"] as? String) ?? ""])
        case "google_web_search": return ("WebSearch", input)
        case "grep_search", "search_file_content": return ("Grep", input)
        case "glob", "list_directory": return ("Glob", input)
        default: return (tool, input)
        }
    }

    private static func cursor(_ json: [String: Any]) -> [[String: Any]] {
        guard let name = json["hook_event_name"] as? String,
              let conversation = (json["conversation_id"] as? String) ?? (json["session_id"] as? String)
        else { return [] }
        let cwd = (json["cwd"] as? String) ?? (json["workspace_roots"] as? [String])?.first
        let session = CodingAgent.cursor.sessionID(conversation)
        func event(_ claudeName: String) -> [String: Any] { base(name: claudeName, session: session, cwd: cwd) }

        switch name {
        case "beforeSubmitPrompt":
            var submit = event("UserPromptSubmit")
            submit["prompt"] = json["prompt"]
            return [submit]
        case "stop":
            return [event("Stop")]
        case "sessionEnd":
            return [event("SessionEnd")]
        case "afterFileEdit":
            // Modification faite : montrée dans l'éditeur de la page Agents.
            guard let path = json["file_path"] as? String else { return [] }
            let first = (json["edits"] as? [[String: Any]])?.first
            var edit = event("PreToolUse")
            edit["tool_name"] = "Edit"
            edit["tool_input"] = ["file_path": path,
                                  "old_string": first?["old_string"] ?? "",
                                  "new_string": first?["new_string"] ?? ""]
            return [edit]
        case "afterShellExecution":
            // Commande lancée puis sa sortie : une étape, et le terminal de la page Agents.
            guard let command = json["command"] as? String else { return [] }
            var pre = event("PreToolUse")
            pre["tool_name"] = "Bash"
            pre["tool_input"] = ["command": command]
            var post = event("PostToolUse")
            post["tool_name"] = "Bash"
            post["tool_input"] = ["command": command]
            post["tool_response"] = ["stdout": json["output"] as? String ?? ""]
            return [pre, post]
        case "postToolUse":
            // Les commandes et les modifications arrivent déjà par leurs propres hooks, plus détaillés.
            guard let tool = json["tool_name"] as? String, !["Shell", "Write", "Edit", "Delete"].contains(tool) else { return [] }
            var pre = event("PreToolUse")
            pre["tool_name"] = cursorTool(tool)
            pre["tool_input"] = json["tool_input"] as? [String: Any] ?? [:]
            return [pre]
        default:
            return []
        }
    }

    private static func cursorTool(_ tool: String) -> String {
        if tool.hasPrefix("MCP:") { return "mcp__" + tool.dropFirst(4) }
        return switch tool {
        case "Task": "Task"
        default: tool
        }
    }

    // MARK: Réponses

    /// Réponse de Notchkit (format de Claude Code) traduite pour l'agent. Toujours un objet JSON :
    /// Gemini CLI et Cursor attendent du JSON sur la sortie de leur hook.
    static func response(_ response: [String: Any]?, to json: [String: Any], agent: CodingAgent) -> [String: Any] {
        let name = json["hook_event_name"] as? String ?? ""
        switch agent {
        case .claude, .codex:
            return response ?? [:]
        case .gemini:
            // Fin de tour : le message de l'encoche relance l'agent (« deny » + raison = nouvelle demande).
            if name == "AfterAgent", response?["decision"] as? String == "block", let reason = response?["reason"] {
                return ["decision": "deny", "reason": reason]
            }
            if name == "AfterTool", let context = additionalContext(response) {
                return ["hookSpecificOutput": ["hookEventName": "AfterTool", "additionalContext": context]]
            }
            return [:]
        case .cursor:
            if name == "beforeSubmitPrompt" { return ["continue": true] }
            if name == "stop", response?["decision"] as? String == "block", let reason = response?["reason"] {
                return ["followup_message": reason]
            }
            return [:]
        }
    }

    /// Événements où l'agent peut recevoir un message envoyé depuis l'encoche.
    static func acceptsMessages(_ agent: CodingAgent, claudeEvent: String) -> Bool {
        switch agent {
        case .claude, .codex: true
        case .gemini: claudeEvent == "Stop" || claudeEvent == "PostToolUse"
        case .cursor: claudeEvent == "Stop"
        }
    }

    // MARK: Utilitaires

    private static func base(name: String, session: String, cwd: String?) -> [String: Any] {
        var event: [String: Any] = ["hook_event_name": name, "session_id": session]
        event["cwd"] = cwd
        return event
    }

    private static func additionalContext(_ response: [String: Any]?) -> Any? {
        (response?["hookSpecificOutput"] as? [String: Any])?["additionalContext"]
    }

    /// Sortie d'une commande : texte brut ou objet, ramenée au format de Claude Code (`stdout`).
    private static func shellResponse(_ value: Any?) -> Any? {
        switch value {
        case let text as String: ["stdout": text]
        case let object as [String: Any]:
            object["stdout"] != nil ? object : ["stdout": (object["output"] ?? object["aggregated_output"]) as? String ?? ""]
        default: nil
        }
    }

    /// Correctif `apply_patch` de Codex → modification (`Edit`) ou fichier créé (`Write`) du premier fichier.
    static func patchEdit(_ patch: String) -> (tool: String, input: [String: Any]) {
        var path: String?
        var isNew = false
        var removed: [String] = []
        var added: [String] = []
        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("*** Update File: ") || line.hasPrefix("*** Add File: ") || line.hasPrefix("*** Delete File: ") {
                // Un seul fichier montré : on s'arrête au deuxième.
                guard path == nil else { break }
                isNew = line.hasPrefix("*** Add File: ")
                path = line.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) }
            } else if line.hasPrefix("-"), !line.hasPrefix("---") {
                removed.append(String(line.dropFirst()))
            } else if line.hasPrefix("+"), !line.hasPrefix("+++") {
                added.append(String(line.dropFirst()))
            }
        }
        let file = path ?? ""
        if isNew { return ("Write", ["file_path": file, "content": added.joined(separator: "\n")]) }
        return ("Edit", ["file_path": file,
                         "old_string": removed.joined(separator: "\n"),
                         "new_string": added.joined(separator: "\n")])
    }

    private static func firstURL(in text: String?) -> String? {
        guard let text else { return nil }
        return text.split(whereSeparator: \.isWhitespace).first { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
            .map(String.init)
    }
}
