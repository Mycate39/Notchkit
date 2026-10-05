import Foundation

/// Message de la conversation avec Claude, tel qu'affiché dans l'encoche.
struct ClaudeChatEntry: Identifiable, Equatable, Sendable {
    enum Role: Sendable, Equatable { case user, claude }

    let id: String
    let role: Role
    let text: String
}

/// Lecture des messages texte dans la transcription d'une session de Claude Code
/// (fichier JSONL indiqué par `transcript_path` dans chaque hook). Logique pure, testable.
enum ClaudeTranscriptParser {
    /// Longueur maximale gardée par message (l'encoche n'affiche pas des pages entières).
    static let maxLength = 4000

    /// Messages texte d'une série de lignes JSONL (réponses de Claude et demandes de l'utilisateur).
    /// Ignorés : réflexion, appels et résultats d'outils, messages internes, sous-agents.
    static func entries(from lines: some Sequence<Substring>) -> [ClaudeChatEntry] {
        var result: [ClaudeChatEntry] = []
        for line in lines {
            guard line.contains("\"text\""),
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String, type == "assistant" || type == "user",
                  json["isMeta"] as? Bool != true, json["isSidechain"] as? Bool != true,
                  json["isCompactSummary"] as? Bool != true,
                  let message = json["message"] as? [String: Any]
            else { continue }

            let texts: [String]
            if let content = message["content"] as? String {
                texts = [content]
            } else if let blocks = message["content"] as? [[String: Any]] {
                texts = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            } else {
                continue
            }
            // Les balises (« <system-reminder> », « <command-name> »…) sont du contexte technique.
            let text = texts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("<") }
                .joined(separator: "\n\n")
            guard !text.isEmpty else { continue }

            let id = json["uuid"] as? String ?? UUID().uuidString
            result.append(ClaudeChatEntry(id: id, role: type == "assistant" ? .claude : .user,
                                          text: String(text.prefix(maxLength))))
        }
        return result
    }
}

/// Lit les nouvelles lignes d'une transcription depuis la dernière lecture (sans tout relire).
actor ClaudeTranscriptReader {
    /// À la première lecture d'un gros fichier, on ne reprend que sa fin.
    static let initialTail: UInt64 = 256 * 1024

    private var offsets: [String: UInt64] = [:]

    /// Nouveaux messages depuis le dernier appel pour ce fichier.
    func newEntries(at path: String) -> [ClaudeChatEntry] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }

        var start = offsets[path] ?? (size > Self.initialTail ? size - Self.initialTail : 0)
        if start > size { start = 0 }  // fichier recréé ou tronqué
        guard start < size, (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty
        else { return [] }

        // On ne traite que les lignes complètes : la dernière peut être en cours d'écriture.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return [] }
        let complete = data[data.startIndex...lastNewline]
        offsets[path] = start + UInt64(complete.count)

        var lines = String(decoding: complete, as: UTF8.self).split(separator: "\n")
        // Reprise au milieu du fichier : la première ligne peut être coupée.
        if start > 0, !lines.isEmpty, !lines[0].hasPrefix("{") { lines.removeFirst() }
        return ClaudeTranscriptParser.entries(from: lines)
    }

    func forget(_ path: String) {
        offsets[path] = nil
    }
}
