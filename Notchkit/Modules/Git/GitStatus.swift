import Foundation

/// État d'un dépôt Git, décodé depuis `git status --porcelain=v2 --branch`.
struct GitStatus: Equatable, Sendable {
    struct Change: Equatable, Sendable, Identifiable {
        enum Kind: Sendable { case modified, added, deleted, renamed, untracked, conflict }
        let path: String
        let kind: Kind
        var id: String { path }
    }

    var branch = ""
    var ahead = 0
    var behind = 0
    var hasUpstream = false
    var changes: [Change] = []

    var isClean: Bool { changes.isEmpty }

    /// Décode la sortie de `git status --porcelain=v2 --branch` (format stable, prévu pour les scripts).
    static func parse(_ output: String) -> GitStatus {
        var status = GitStatus()
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: false)
            switch fields.first {
            case "#":
                if fields.count >= 3, fields[1] == "branch.head" {
                    status.branch = fields[2] == "(detached)" ? "HEAD" : String(fields[2])
                } else if fields.count >= 4, fields[1] == "branch.ab" {
                    status.hasUpstream = true
                    status.ahead = Int(fields[2].dropFirst()) ?? 0
                    status.behind = Int(fields[3].dropFirst()) ?? 0
                }
            case "1":
                // 1 XY sub mH mI mW hH hI chemin
                guard fields.count >= 9 else { continue }
                let xy = fields[1]
                let kind: Change.Kind = xy.contains("D") ? .deleted : xy.contains("A") ? .added : .modified
                status.changes.append(Change(path: fields[8...].joined(separator: " "), kind: kind))
            case "2":
                // 2 XY sub mH mI mW hH hI X100 chemin<tab>ancien
                guard fields.count >= 10 else { continue }
                let path = fields[9...].joined(separator: " ").split(separator: "\t").first.map(String.init) ?? ""
                status.changes.append(Change(path: path, kind: .renamed))
            case "u":
                guard fields.count >= 11 else { continue }
                status.changes.append(Change(path: fields[10...].joined(separator: " "), kind: .conflict))
            case "?":
                status.changes.append(Change(path: fields.dropFirst().joined(separator: " "), kind: .untracked))
            default:
                continue
            }
        }
        return status
    }
}

/// Appels à l'outil `git` du Mac (Command Line Tools), hors du fil principal.
enum GitCommand {
    static let executable = URL(fileURLWithPath: "/usr/bin/git")

    /// Lance git dans `directory` et renvoie la sortie standard (`nil` en cas d'échec).
    static func run(_ arguments: [String], in directory: URL) async -> String? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["-C", directory.path] + arguments
            // Jamais de demande interactive (mot de passe, éditeur) : on échoue plutôt que d'attendre.
            process.environment = ProcessInfo.processInfo.environment.merging(
                ["GIT_TERMINAL_PROMPT": "0", "GIT_EDITOR": "true"], uniquingKeysWith: { $1 })
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
        }.value
    }

    /// Racine du dépôt qui contient `url` (fichier ou dossier), s'il y en a un.
    static func repositoryRoot(containing url: URL) async -> URL? {
        let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        guard let output = await run(["rev-parse", "--show-toplevel"], in: directory) else { return nil }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
    }
}
