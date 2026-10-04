import Foundation

/// Estimation de l'utilisation de Claude Code à partir de ses fichiers de session locaux
/// (`~/.claude/projects/*/*.jsonl`). Aucune donnée ne quitte le Mac, aucun identifiant n'est lu.
///
/// ⚠️ C'est une estimation : Anthropic ne publie pas les plafonds exacts des abonnements,
/// et seule l'utilisation de Claude Code est comptée (pas les conversations sur claude.ai).
struct ClaudeUsageSummary: Equatable, Sendable {
    /// Tokens consommés dans la session de 5 h en cours (0 si aucune).
    let currentTokens: Int
    /// Fin de la session de 5 h en cours, `nil` si aucune n'est en cours.
    let resetAt: Date?
    /// Plus grosse session observée : sert de repère pour la jauge.
    let personalMax: Int

    /// Part de la session utilisée (0…1), par rapport à la plus grosse session observée.
    /// `nil` s'il n'y a pas de session en cours ou pas encore de repère.
    var usedFraction: Double? {
        guard resetAt != nil, personalMax > 0 else { return nil }
        return min(1, Double(currentTokens) / Double(personalMax))
    }
}

struct ClaudeUsageEntry: Equatable, Sendable {
    let date: Date
    let tokens: Int
}

struct ClaudeUsageBlock: Equatable, Sendable {
    let start: Date
    var tokens: Int
    var end: Date { start.addingTimeInterval(ClaudeUsageCalculator.blockDuration) }
}

enum ClaudeUsageCalculator {
    /// Les limites des abonnements Claude se réinitialisent par sessions de 5 heures.
    static let blockDuration: TimeInterval = 5 * 3600

    /// Découpe les consommations en sessions de 5 h : une session commence à l'heure pleine
    /// du premier message, et la suivante au premier message après sa fin.
    static func blocks(from entries: [ClaudeUsageEntry], calendar: Calendar = .current) -> [ClaudeUsageBlock] {
        var blocks: [ClaudeUsageBlock] = []
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            if var last = blocks.last, entry.date < last.end {
                last.tokens += entry.tokens
                blocks[blocks.count - 1] = last
            } else {
                let start = calendar.dateInterval(of: .hour, for: entry.date)?.start ?? entry.date
                blocks.append(ClaudeUsageBlock(start: start, tokens: entry.tokens))
            }
        }
        return blocks
    }

    static func summary(from entries: [ClaudeUsageEntry], storedMax: Int, now: Date = Date()) -> ClaudeUsageSummary {
        let blocks = blocks(from: entries)
        let current = blocks.last.flatMap { $0.end > now ? $0 : nil }
        let observedMax = blocks.map(\.tokens).max() ?? 0
        return ClaudeUsageSummary(
            currentTokens: current?.tokens ?? 0,
            resetAt: current?.end,
            personalMax: max(storedMax, observedMax)
        )
    }

    /// Lit une ligne de transcription : seules les réponses de Claude portent une consommation.
    /// On compte les tokens d'entrée, de sortie et d'écriture en cache (les lectures de cache,
    /// très nombreuses et bien moins coûteuses, sont exclues).
    /// Renvoie aussi un identifiant pour éliminer les doublons (une réponse occupe plusieurs lignes).
    static func parse(line: Data) -> (id: String, entry: ClaudeUsageEntry)? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let timestamp = object["timestamp"] as? String,
              let date = parseDate(timestamp)
        else { return nil }

        func count(_ key: String) -> Int { usage[key] as? Int ?? 0 }
        let tokens = count("input_tokens") + count("output_tokens") + count("cache_creation_input_tokens")
        let id = "\(message["id"] as? String ?? UUID().uuidString)|\(object["requestId"] as? String ?? "")"
        return (id, ClaudeUsageEntry(date: date, tokens: tokens))
    }

    static func parseDate(_ string: String) -> Date? {
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return (try? withFraction.parse(string)) ?? (try? Date.ISO8601FormatStyle().parse(string))
    }
}

/// Lecture des fichiers, hors du thread principal.
enum ClaudeUsageLoader {
    static var projectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Consommations depuis `since` (seuls les fichiers modifiés depuis sont lus).
    static func entries(since: Date) async -> [ClaudeUsageEntry] {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            guard let projects = try? fileManager.contentsOfDirectory(
                at: projectsDirectory, includingPropertiesForKeys: nil
            ) else { return [] }

            var seen = Set<String>()
            var entries: [ClaudeUsageEntry] = []
            let marker = Data("\"usage\"".utf8)

            for project in projects {
                guard let files = try? fileManager.contentsOfDirectory(
                    at: project, includingPropertiesForKeys: [.contentModificationDateKey]
                ) else { continue }
                for file in files where file.pathExtension == "jsonl" {
                    let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    guard let modified, modified >= since, let data = try? Data(contentsOf: file) else { continue }

                    for line in data.split(separator: 0x0A) where line.range(of: marker) != nil {
                        guard let (id, entry) = ClaudeUsageCalculator.parse(line: Data(line)),
                              entry.date >= since, seen.insert(id).inserted
                        else { continue }
                        entries.append(entry)
                    }
                }
            }
            return entries
        }.value
    }
}
