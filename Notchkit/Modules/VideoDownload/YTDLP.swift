import Foundation

import CryptoKit

/// Outil yt-dlp (logiciel libre, domaine public), installé séparément.
/// Notchkit ne l'intègre pas : il l'utilise s'il est présent, ou le télécharge à la demande
/// depuis les publications officielles du projet (dans le dossier de Notchkit).
enum YTDLP {
    /// Dossier où Notchkit installe yt-dlp lui-même (~/Library/Application Support/Notchkit/bin).
    static var managedDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Notchkit/bin", isDirectory: true)
    }

    static var searchPaths: [String] {
        [managedDirectory.path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
    }

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
            case .bestVideo: "Vidéo"
            case .video1080: "Vidéo 1080p"
            case .video720: "Vidéo 720p"
            case .audioM4A: "Audio (M4A)"
            case .audioMP3: "Audio (MP3)"
            }
        }

        /// Libellé court, pour les petits widgets.
        var shortTitle: String {
            switch self {
            case .bestVideo: String(localized: "Vidéo")
            case .video1080: "1080p"
            case .video720: "720p"
            case .audioM4A: "M4A"
            case .audioMP3: "MP3"
            }
        }

        var isAudio: Bool { self == .audioM4A || self == .audioMP3 }
        /// Choix proposés dans le menu : la résolution se choisit ensuite, d'après la vidéo.
        /// (1080p et 720p restent pour décoder les anciens réglages.)
        static let menuCases: [Format] = [.bestVideo, .audioM4A, .audioMP3]
        /// Le MP3 nécessite ffmpeg (conversion).
        var requiresFFmpeg: Bool { self == .audioMP3 }
    }

    /// Arguments de yt-dlp pour un téléchargement (fonction pure, testée).
    /// - Parameter height: résolution choisie parmi celles de la vidéo (`availableHeights`), ou `nil`.
    static func arguments(url: String, format: Format, directory: URL, hasFFmpeg: Bool, ffmpegLocation: URL?,
                          height: Int? = nil) -> [String] {
        var args = [
            "--newline", "--no-playlist", "--no-colors",
            "--print", "before_dl:NOTCHKIT_TITLE %(title)s",
            "--print", "before_dl:NOTCHKIT_VCODEC %(vcodec)s",
            "--print", "before_dl:NOTCHKIT_DURATION %(duration)s",
            "--print", "after_move:NOTCHKIT_FILE %(filepath)s",
            "--no-simulate",
            "-o", directory.appendingPathComponent("%(title)s.%(ext)s").path,
        ]
        if let ffmpegLocation { args += ["--ffmpeg-location", ffmpegLocation.path] }

        func video(maxHeight: Int?) -> [String] {
            let limit = maxHeight.map { "[height<=\($0)]" } ?? ""
            if hasFFmpeg, let height {
                // Résolution exacte : H.264 si YouTube en propose (jusqu'en 1080p), sinon SDR de
                // préférence (la conversion HEVC qui suit ne gère pas le HDR), sinon ce qui existe.
                let exact = "[height=\(height)]"
                let h264 = height <= 1080 ? "bv*\(exact)[vcodec^=avc1]+ba[ext=m4a]/" : ""
                return ["-f", h264 + "bv*\(exact)[dynamic_range=SDR]+ba[ext=m4a]/bv*\(exact)+ba[ext=m4a]/"
                            + "bv*\(exact)+ba/b[height<=\(height)]",
                        "--merge-output-format", "mp4"]
            }
            if hasFFmpeg {
                // Vidéo et son séparés, assemblés en MP4 par ffmpeg. H.264 d'abord : lisible par
                // QuickTime sur tous les Mac (YouTube le propose jusqu'en 1080p), alors que l'AV1
                // de la 4K ne se décode qu'à partir des puces M3. Sinon, le meilleur MP4 disponible.
                return ["-f", "bv*\(limit)[vcodec^=avc1]+ba[ext=m4a]/b\(limit)[vcodec^=avc1]/"
                            + "bv*\(limit)[ext=mp4]+ba[ext=m4a]/b\(limit)[ext=mp4]/b\(limit)",
                        "--merge-output-format", "mp4"]
            }
            // Sans ffmpeg : un seul fichier contenant déjà image et son, en H.264 si possible.
            return ["-f", "b\(limit)[vcodec^=avc1]/b\(limit)[ext=mp4]/b\(limit)"]
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

    /// Message d'erreur affiché à l'utilisateur (fonction pure, testée). Sans ffmpeg, YouTube ne
    /// propose souvent aucun fichier contenant à la fois l'image et le son : yt-dlp répond alors
    /// « Requested format is not available », qu'on remplace par la marche à suivre.
    static func displayError(_ message: String, hasFFmpeg: Bool) -> String {
        guard !hasFFmpeg, message.contains("Requested format is not available") else { return message }
        return String(localized: "Cette vidéo nécessite ffmpeg pour assembler l'image et le son : installez-le dans le Terminal avec « brew install ffmpeg ».")
    }

    /// Ligne de sortie de yt-dlp interprétée.
    enum OutputLine: Equatable, Sendable {
        case title(String)
        /// Codec vidéo retenu (ex. « avc1.64002A », « av01.0.13M.10 »).
        case videoCodec(String)
        /// Durée en secondes (pour suivre la conversion).
        case duration(Double)
        case progress(percent: Double, detail: String)
        case file(String)
        case error(String)
    }

    /// Interprète une ligne de sortie (fonction pure, testée).
    static func parse(_ line: String) -> OutputLine? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("NOTCHKIT_TITLE ") { return .title(String(trimmed.dropFirst(15))) }
        if trimmed.hasPrefix("NOTCHKIT_VCODEC ") {
            let codec = String(trimmed.dropFirst(16))
            return codec == "none" || codec == "NA" ? nil : .videoCodec(codec)
        }
        if trimmed.hasPrefix("NOTCHKIT_DURATION ") { return Double(trimmed.dropFirst(18)).map(OutputLine.duration) }
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

    // MARK: Résolutions

    /// Arguments pour lire la description d'une vidéo (formats compris) sans la télécharger.
    static func probeArguments(url: String) -> [String] {
        ["--no-playlist", "--no-colors", "--no-warnings", "-J", "--", url]
    }

    /// Hauteurs d'image proposées par la vidéo, de la plus grande à la plus petite (fonction pure,
    /// testée), lues dans la sortie JSON de `yt-dlp -J`. Ignore les pistes audio et les planches
    /// d'aperçu.
    static func availableHeights(json: Data) -> [Int] {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let formats = object["formats"] as? [[String: Any]]
        else { return [] }
        let heights = formats.compactMap { format -> Int? in
            guard let codec = format["vcodec"] as? String, codec != "none", format["ext"] as? String != "mhtml",
                  let height = format["height"] as? Int, height > 0
            else { return nil }
            return height
        }
        return Array(Set(heights)).sorted(by: >)
    }

    /// Libellé d'une résolution (« 2160p »).
    static func label(height: Int) -> String { "\(height)p" }

    // MARK: Conversion HEVC

    /// L'AV1 et le VP9 (seuls codecs de YouTube au-delà de 1080p) ne se lisent pas dans QuickTime
    /// sur tous les Mac : on les convertit en HEVC (fonction pure, testée).
    static func needsConversion(videoCodec: String?) -> Bool {
        guard let codec = videoCodec?.lowercased() else { return false }
        return ["av01", "vp09", "vp9", "vp8"].contains { codec.hasPrefix($0) }
    }

    /// Débit HEVC visé selon la hauteur d'image.
    static func hevcBitrate(height: Int?) -> String {
        switch height ?? 1080 {
        case 2000...: "20M"
        case 1300...: "12M"
        case 1000...: "8M"
        default: "5M"
        }
    }

    /// Arguments de ffmpeg pour convertir en HEVC avec l'encodeur matériel du Mac (VideoToolbox),
    /// son copié tel quel, progression sur la sortie standard.
    static func conversionArguments(input: URL, output: URL, height: Int?) -> [String] {
        ["-nostdin", "-y", "-i", input.path,
         "-map", "0:v:0", "-map", "0:a?",
         "-c:v", "hevc_videotoolbox", "-profile:v", "main10", "-pix_fmt", "p010le",
         "-b:v", hevcBitrate(height: height), "-tag:v", "hvc1",
         "-c:a", "copy", "-movflags", "+faststart",
         "-progress", "pipe:1", "-nostats", output.path]
    }

    /// Avancement de la conversion d'après une ligne de `-progress` (« out_time_us=… »).
    static func conversionProgress(_ line: String, duration: Double) -> Double? {
        guard duration > 0, line.hasPrefix("out_time_us="), let micros = Double(line.dropFirst(12)) else { return nil }
        return min(max(micros / 1_000_000 / duration, 0), 1)
    }

    /// Lien plausible (http/https).
    static func isValidLink(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host() != nil
        else { return false }
        return true
    }
}

// MARK: - Installation directe

/// Télécharge le programme officiel `yt-dlp_macos` (universel : Intel et Apple Silicon)
/// depuis GitHub et vérifie son empreinte SHA-256 avant de l'installer.
///
/// Évite Homebrew, qui ne fournit plus de versions précompilées pour les Mac Intel
/// (il faudrait compiler LLVM et Rust : des heures, souvent en échec).
enum YTDLPInstaller {
    static let releaseBase = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/")!
    static let assetName = "yt-dlp_macos"

    enum InstallError: LocalizedError {
        case missingChecksum
        case checksumMismatch

        var errorDescription: String? {
            switch self {
            case .missingChecksum: String(localized: "Empreinte de vérification introuvable.")
            case .checksumMismatch: String(localized: "Le fichier téléchargé est corrompu (empreinte différente). Réessayez.")
            }
        }
    }

    /// Empreinte attendue pour `name` dans un fichier SHA2-256SUMS (« empreinte  nom » par ligne).
    static func expectedHash(for name: String, in sums: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count == 2, parts[1] == name { return parts[0].lowercased() }
        }
        return nil
    }

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Télécharge, vérifie et installe yt-dlp. Renvoie l'emplacement de l'exécutable.
    @discardableResult
    static func install(session: URLSession = .shared) async throws -> URL {
        let (sumsData, _) = try await session.data(from: releaseBase.appendingPathComponent("SHA2-256SUMS"))
        guard let expected = expectedHash(for: assetName, in: String(decoding: sumsData, as: UTF8.self)) else {
            throw InstallError.missingChecksum
        }
        let (binary, _) = try await session.data(from: releaseBase.appendingPathComponent(assetName))
        guard sha256(of: binary) == expected else { throw InstallError.checksumMismatch }

        let directory = YTDLP.managedDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("yt-dlp")
        try binary.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        return destination
    }
}
