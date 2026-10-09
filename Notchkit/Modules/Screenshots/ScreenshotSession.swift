import Foundation

/// Une capture (image) ou un enregistrement d'écran (vidéo).
struct Screenshot: Identifiable, Equatable, Sendable {
    let url: URL
    let date: Date
    let isVideo: Bool

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

/// Logique pure du module Captures d'écran : début de session, reconnaissance, tri.
enum ScreenshotSession {
    /// Début de la session : le plus récent entre le démarrage du Mac et l'ouverture de session.
    static func start(boot: Date?, login: Date?) -> Date {
        [boot, login].compactMap { $0 }.max() ?? .distantPast
    }

    /// Préfixes des enregistrements d'écran de macOS (ils n'ont pas toujours l'étiquette Spotlight
    /// des captures, on les reconnaît alors à leur nom).
    static let recordingPrefixes = ["Screen Recording", "Enregistrement de l’écran", "Enregistrement de l'écran"]

    static func isScreenRecording(fileName: String) -> Bool {
        recordingPrefixes.contains { fileName.hasPrefix($0) }
    }

    /// Captures de la session, de la plus récente à la plus ancienne, sans doublons.
    static func sessionItems(_ items: [Screenshot], since start: Date) -> [Screenshot] {
        var seen = Set<URL>()
        return items
            .filter { $0.date >= start && seen.insert($0.url.standardizedFileURL).inserted }
            .sorted { $0.date > $1.date }
    }

    /// Démarrage du Mac (`kern.boottime`).
    static var bootDate: Date? {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0, time.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }

    /// Ouverture de la session graphique de l'utilisateur (registre utmpx, ligne « console »).
    static var loginDate: Date? {
        let user = NSUserName()
        var latest: Date?
        setutxent()
        defer { endutxent() }
        while let entry = getutxent() {
            guard entry.pointee.ut_type == USER_PROCESS else { continue }
            let name = withUnsafeBytes(of: entry.pointee.ut_user) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let line = withUnsafeBytes(of: entry.pointee.ut_line) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            guard name == user, line == "console" else { continue }
            let date = Date(timeIntervalSince1970: TimeInterval(entry.pointee.ut_tv.tv_sec))
            if latest.map({ date > $0 }) ?? true { latest = date }
        }
        return latest
    }
}
