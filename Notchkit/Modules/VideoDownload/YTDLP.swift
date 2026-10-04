import Foundation

/// Outil yt-dlp (logiciel libre, domaine public), installé séparément avec Homebrew.
/// Notchkit ne l'intègre pas : il l'utilise s'il est présent.
enum YTDLP {
    static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]

    static func locate(_ tool: String) -> URL? {
        searchPaths.map { URL(fileURLWithPath: $0).appendingPathComponent(tool) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var executable: URL? { locate("yt-dlp") }
    static var ffmpeg: URL? { locate("ffmpeg") }
    static var brew: URL? { locate("brew") }

    /// Formats proposés.
    enum Format: String, CaseIterable, Identifiable, Codable, Sendable {
        case bestVideo, video1080, video720, audioM4A, audioMP3
        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .bestVideo: "Vidéo (meilleure qualité)"
            case .video1080: "Vidéo 1080p"
            case .video720: "Vidéo 720p"
            case .audioM4A: "Audio (M4A)"
            case .audioMP3: "Audio (MP3)"
            }
        }

        var isAudio: Bool { self == .audioM4A || self == .audioMP3 }
        /// Le MP3 nécessite ffmpeg (conversion).
        var requiresFFmpeg: Bool { self == .audioMP3 }
    }

    /// Arguments de yt-dlp pour un téléchargement (fonction pure, testée).
    static func arguments(url: String, format: Format, directory: URL, hasFFmpeg: Bool, ffmpegLocation: URL?) -> [String] {
        var args = [
            "--newline", "--no-playlist", "--no-colors",
            "--print", "before_dl:NOTCHKIT_TITLE %(title)s",
            "--print", "after_move:NOTCHKIT_FILE %(filepath)s",
            "--no-simulate",
            "-o", directory.appendingPathComponent("%(title)s.%(ext)s").path,
        ]
        if let ffmpegLocation { args += ["--ffmpeg-location", ffmpegLocation.path] }

        func video(maxHeight: Int?) -> [String] {
            let limit = maxHeight.map { "[height<=\($0)]" } ?? ""
            if hasFFmpeg {
                // Vidéo et son séparés (meilleure qualité), assemblés en MP4 par ffmpeg.
                return ["-f", "bv*\(limit)[ext=mp4]+ba[ext=m4a]/b\(limit)[ext=mp4]/b\(limit)", "--merge-output-format", "mp4"]
            }
            // Sans ffmpeg : un seul fichier contenant déjà image et son.
            return ["-f", "b\(limit)[ext=mp4]/b\(limit)"]
        }

        switch format {
        case .bestVideo: args += video(maxHeight: nil)
        case .video1080: args += video(maxHeight: 1080)
        case .video720: args += video(maxHeight: 720)
        case .audioM4A: args += ["-f", "ba[ext=m4a]/ba"]
        case .audioMP3: args += ["-f", "ba", "-x", "--audio-format", "mp3"]
        }
        return args + ["--", url]
    }

    /// Ligne de sortie de yt-dlp interprétée.
    enum OutputLine: Equatable, Sendable {
        case title(String)
        case progress(percent: Double, detail: String)
        case file(String)
        case error(String)
    }

    /// Interprète une ligne de sortie (fonction pure, testée).
    static func parse(_ line: String) -> OutputLine? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("NOTCHKIT_TITLE ") { return .title(String(trimmed.dropFirst(15))) }
        if trimmed.hasPrefix("NOTCHKIT_FILE ") { return .file(String(trimmed.dropFirst(14))) }
        if trimmed.hasPrefix("ERROR:") { return .error(String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)) }
        // Ex. « [download]  42.3% of   12.34MiB at    2.10MiB/s ETA 00:05 »
        guard trimmed.hasPrefix("[download]"),
              let percentRange = trimmed.range(of: #"\d+(\.\d+)?%"#, options: .regularExpression),
              let percent = Double(trimmed[percentRange].dropLast())
        else { return nil }
        var detail = ""
        if let eta = trimmed.range(of: #"ETA\s+\S+"#, options: .regularExpression) {
            detail = String(trimmed[eta]).replacingOccurrences(of: "ETA", with: String(localized: "reste"))
        }
        if let speed = trimmed.range(of: #"at\s+\S+/s"#, options: .regularExpression) {
            let value = trimmed[speed].replacingOccurrences(of: "at", with: "").trimmingCharacters(in: .whitespaces)
            detail = detail.isEmpty ? value : "\(value) · \(detail)"
        }
        return .progress(percent: percent / 100, detail: detail)
    }

    /// Lien plausible (http/https).
    static func isValidLink(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host() != nil
        else { return false }
        return true
    }
}
