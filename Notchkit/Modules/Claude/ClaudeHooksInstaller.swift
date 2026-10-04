import Foundation

/// Installe ou retire les hooks HTTP de Notchkit dans `~/.claude/settings.json`.
///
/// - les réglages existants de l'utilisateur sont conservés (seules nos entrées sont touchées) ;
/// - une copie de sauvegarde du fichier est faite avant chaque modification ;
/// - nos entrées sont reconnues à leur URL (`/notchkit/claude/hook`).
enum ClaudeHooksInstaller {
    enum InstallerError: LocalizedError {
        case unreadableSettings

        var errorDescription: String? {
            String(localized: "Le fichier ~/.claude/settings.json n'est pas un JSON valide. Corrigez-le ou supprimez-le, puis réessayez.")
        }
    }

    /// Événements écoutés. Ceux qui portent sur des outils ou des notifications ont un filtre « * ».
    static let events: [(name: String, needsMatcher: Bool)] = [
        ("UserPromptSubmit", false),
        ("PreToolUse", true),
        ("PostToolUse", true),
        ("Stop", false),
        ("Notification", true),
        ("SessionEnd", false),
    ]

    /// Version de notre configuration : à incrémenter quand elle change (une réinstallation est alors proposée).
    static let version = "2"
    /// Le hook Stop peut rester ouvert pendant la fenêtre de réponse (au plus 4 min) : délai plus long.
    static let stopTimeout = 300
    static let defaultTimeout = 10

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    static func hookURL(port: UInt16) -> String {
        "http://127.0.0.1:\(port)\(ClaudeHookServer.path)"
    }

    // MARK: - Transformations (pures, testées)

    static func installing(into settings: [String: Any], port: UInt16, token: String) -> [String: Any] {
        var result = removing(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        for event in events {
            let hook: [String: Any] = [
                "type": "http",
                "url": hookURL(port: port),
                "timeout": event.name == "Stop" ? stopTimeout : defaultTimeout,
                "headers": ["X-Notchkit-Token": token, "X-Notchkit-Version": version],
            ]
            var groups = hooks[event.name] as? [[String: Any]] ?? []
            var group: [String: Any] = ["hooks": [hook]]
            if event.needsMatcher { group["matcher"] = "*" }
            groups.append(group)
            hooks[event.name] = groups
        }
        result["hooks"] = hooks
        return result
    }

    static func removing(from settings: [String: Any]) -> [String: Any] {
        var result = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return result }

        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let cleaned: [[String: Any]] = groups.compactMap { group in
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

    /// Vrai si nos hooks sont présents pour tous les événements, avec le bon port et le bon jeton.
    static func isInstalled(in settings: [String: Any], port: UInt16, token: String) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            let groups = hooks[event.name] as? [[String: Any]] ?? []
            return groups.contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { entry in
                    let headers = entry["headers"] as? [String: Any]
                    return entry["url"] as? String == hookURL(port: port)
                        && headers?["X-Notchkit-Token"] as? String == token
                        && headers?["X-Notchkit-Version"] as? String == version
                }
            }
        }
    }

    /// Vrai si des hooks de Notchkit sont présents (même anciens ou incomplets).
    static func hasOurHooks(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs)
            }
        }
    }

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        (entry["url"] as? String)?.contains(ClaudeHookServer.path) == true
    }

    // MARK: - Fichier

    static func readSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL) else { return [:] }
        if data.isEmpty { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallerError.unreadableSettings
        }
        return object
    }

    enum Status: Equatable {
        case notInstalled
        /// Nos hooks sont présents mais d'une version précédente : réinstaller pour les mettre à jour.
        case outdated
        case installed
    }

    static func status(port: UInt16, token: String) -> Status {
        guard let settings = try? readSettings() else { return .notInstalled }
        if isInstalled(in: settings, port: port, token: token) { return .installed }
        return hasOurHooks(in: settings) ? .outdated : .notInstalled
    }

    /// Installe les hooks. Renvoie l'emplacement de la sauvegarde (s'il y avait un fichier).
    @discardableResult
    static func install(port: UInt16, token: String) throws -> URL? {
        let settings = try readSettings()
        return try write(installing(into: settings, port: port, token: token))
    }

    @discardableResult
    static func uninstall() throws -> URL? {
        let settings = try readSettings()
        return try write(removing(from: settings))
    }

    private static func write(_ settings: [String: Any]) throws -> URL? {
        let fileManager = FileManager.default
        let directory = settingsURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var backup: URL?
        if fileManager.fileExists(atPath: settingsURL.path) {
            let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                .replacingOccurrences(of: ":", with: "-")
            let url = directory.appendingPathComponent("settings.json.notchkit-backup-\(stamp)")
            try? fileManager.removeItem(at: url)
            try fileManager.copyItem(at: settingsURL, to: url)
            backup = url
        }

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
        return backup
    }
}
