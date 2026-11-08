import Foundation

/// Installe ou retire les hooks de Notchkit pour Codex, Gemini CLI et Cursor.
///
/// Ces agents n'ont que des hooks « commande » : chacun lance `agent-hook.sh`, qui relaie le JSON reçu au
/// serveur local de Notchkit et renvoie sa réponse. Comme pour Claude Code, les réglages existants sont
/// conservés, une sauvegarde est faite avant chaque modification et nos entrées sont reconnues au nom
/// du script.
enum AgentHooksInstaller {
    static let scriptName = "agent-hook.sh"
    /// Version de notre configuration : à incrémenter quand elle change (elle est alors réécrite).
    static let version = "1"
    /// Codex attend la décision prise dans l'encoche au plus ce temps (secondes), puis pose sa question.
    static let decisionTimeout = 120
    static let eventTimeout = 5

    static var scriptURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchkit", isDirectory: true)
            .appendingPathComponent(scriptName)
    }

    static func script(port: UInt16, token: String) -> String {
        #"""
        #!/bin/sh
        # Généré par Notchkit (version \#(version)). Relaie l'activité d'un agent de code à Notchkit (connexion
        # locale uniquement, protégée par un jeton) et renvoie sa réponse. Sans Notchkit : réponse neutre.
        # Arguments : agent, 1 si Notchkit peut attendre une décision.
        agent="$1"
        wait="${2:-0}"
        if [ "$wait" = 1 ]; then max=\#(decisionTimeout - 5); else max=\#(eventTimeout - 2); fi
        out=$(/usr/bin/curl -s -m "$max" -X POST \
          -H 'X-Notchkit-Token: \#(token)' -H "X-Notchkit-Agent: $agent" -H "X-Notchkit-Wait: $wait" \
          -H 'Content-Type: application/json' --data-binary @- \
          'http://127.0.0.1:\#(port)\#(AgentHookTranslator.path)' 2>/dev/null)
        if [ -n "$out" ]; then printf '%s\n' "$out"; else printf '{}\n'; fi
        exit 0

        """#
    }

    /// Commande d'un hook (chemin entre guillemets : « Application Support » contient une espace).
    static func command(for agent: CodingAgent, wait: Bool = false) -> String {
        "'\(scriptURL.path)' \(agent.rawValue) \(wait ? 1 : 0)"
    }

    // MARK: Transformations (pures, testées)

    static func installing(into settings: [String: Any], agent: CodingAgent) -> [String: Any] {
        var result = removing(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        switch agent {
        case .codex:
            for event in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd", "PermissionRequest"] {
                let wait = event == "PermissionRequest"
                var hook: [String: Any] = ["type": "command", "command": command(for: .codex, wait: wait),
                                           "timeout": wait ? decisionTimeout : eventTimeout]
                if wait { hook["statusMessage"] = "Waiting for your answer in Notchkit" }
                append(["hooks": [hook]], to: event, in: &hooks)
            }
        case .gemini:
            for event in ["BeforeAgent", "BeforeTool", "AfterTool", "AfterAgent", "SessionEnd", "Notification"] {
                var group: [String: Any] = ["hooks": [[
                    "name": "notchkit", "type": "command", "command": command(for: .gemini),
                    "timeout": eventTimeout * 1000, // millisecondes
                ]]]
                if event == "BeforeTool" || event == "AfterTool" { group["matcher"] = "*" }
                append(group, to: event, in: &hooks)
            }
        case .cursor:
            result["version"] = result["version"] ?? 1
            for event in ["beforeSubmitPrompt", "postToolUse", "afterShellExecution", "afterFileEdit", "stop", "sessionEnd"] {
                hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [["command": command(for: .cursor), "timeout": eventTimeout]]
            }
        case .claude:
            return settings
        }
        result["hooks"] = hooks
        return result
    }

    private static func append(_ group: [String: Any], to event: String, in hooks: inout [String: Any]) {
        hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [group]
    }

    /// Retire nos hooks, en gardant ceux de l'utilisateur.
    static func removing(from settings: [String: Any]) -> [String: Any] {
        var result = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return result }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let cleaned: [[String: Any]] = groups.compactMap { group in
                // Cursor : chaque entrée est directement un hook.
                if isOurs(group) { return nil }
                guard let entries = group["hooks"] as? [[String: Any]] else { return group }
                let kept = entries.filter { !isOurs($0) }
                if kept.isEmpty { return nil }
                var copy = group
                copy["hooks"] = kept
                return copy
            }
            hooks[event] = cleaned.isEmpty ? nil : cleaned
        }
        result["hooks"] = hooks.isEmpty ? nil : hooks
        return result
    }

    /// Nos hooks sont présents, à la version actuelle (le script, lui, est vérifié à part).
    static func isInstalled(in settings: [String: Any], agent: CodingAgent) -> Bool {
        let expected = installing(into: settings, agent: agent)
        return NSDictionary(dictionary: expected).isEqual(to: settings)
    }

    static func hasOurHooks(in settings: [String: Any]) -> Bool {
        NSDictionary(dictionary: removing(from: settings)).isEqual(to: settings) == false
    }

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        (entry["command"] as? String)?.contains(scriptName) == true
    }

    // MARK: Fichiers

    enum Status: Equatable {
        /// L'agent n'est pas installé sur ce Mac (pas de dossier de configuration).
        case unavailable
        case notInstalled
        case outdated
        case installed
    }

    enum InstallerError: LocalizedError {
        case unreadable(URL)

        var errorDescription: String? {
            switch self {
            case let .unreadable(url):
                String(localized: "Le fichier \(url.path) n'est pas un JSON valide. Corrigez-le, puis réessayez.")
            }
        }
    }

    static func readSettings(_ agent: CodingAgent) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: agent.hooksFile), !data.isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallerError.unreadable(agent.hooksFile)
        }
        return object
    }

    static func status(_ agent: CodingAgent, port: UInt16, token: String) -> Status {
        guard FileManager.default.fileExists(atPath: agent.configDirectory.path) else { return .unavailable }
        guard let settings = try? readSettings(agent) else { return .notInstalled }
        let scriptIsCurrent = (try? String(contentsOf: scriptURL, encoding: .utf8)) == script(port: port, token: token)
        if isInstalled(in: settings, agent: agent) && scriptIsCurrent { return .installed }
        return hasOurHooks(in: settings) ? .outdated : .notInstalled
    }

    /// Écrit le script et les hooks. Renvoie l'emplacement de la sauvegarde (s'il y avait un fichier).
    @discardableResult
    static func install(_ agent: CodingAgent, port: UInt16, token: String) throws -> URL? {
        let settings = try readSettings(agent)
        try writeScript(port: port, token: token)
        return try write(installing(into: settings, agent: agent), to: agent.hooksFile)
    }

    /// Réécrit le script (port ou jeton changés) sans toucher aux réglages des agents.
    static func writeScript(port: UInt16, token: String) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(script(port: port, token: token).utf8).write(to: scriptURL, options: .atomic)
        // Lisible par l'utilisateur seul : il contient le jeton.
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
    }

    @discardableResult
    static func uninstall(_ agent: CodingAgent) throws -> URL? {
        let settings = try readSettings(agent)
        return try write(removing(from: settings), to: agent.hooksFile)
    }

    private static func write(_ settings: [String: Any], to url: URL) throws -> URL? {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var backup: URL?
        if fileManager.fileExists(atPath: url.path) {
            let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                .replacingOccurrences(of: ":", with: "-")
            let copy = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).notchkit-backup-\(stamp)")
            try? fileManager.removeItem(at: copy)
            try fileManager.copyItem(at: url, to: copy)
            backup = copy
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        return backup
    }
}
