import AppKit

/// Commandes de lecture envoyées au lecteur actif.
enum PlaybackCommand: Sendable {
    case togglePlayPause
    case nextTrack
    case previousTrack
}

/// Morceau en cours, quelle que soit la source qui l'a fourni.
struct NowPlayingInfo {
    /// Source qui a fourni l'information (détermine aussi par où passent les commandes).
    enum Origin: Hashable, Sendable {
        case mediaRemote
        case appleMusic
        case spotify
    }

    var origin: Origin
    /// App qui joue (ex. « com.brave.Browser » pour Deezer dans Brave).
    var bundleIdentifier: String?
    var title: String
    var artist: String?
    var album: String?
    var isPlaying: Bool
    /// Durée totale en secondes.
    var duration: TimeInterval?
    /// Position en secondes, mesurée à l'instant `timestamp`.
    var elapsed: TimeInterval?
    var timestamp: Date?
    var playbackRate: Double = 1
    var artwork: NSImage?
    /// Empreinte de la pochette, pour détecter un changement sans comparer les images.
    var artworkHash: Int?
    /// Date de réception (pour départager plusieurs sources).
    var receivedAt = Date()

    /// Position estimée à une date donnée (avance tant que la lecture est en cours).
    func elapsed(at date: Date) -> TimeInterval? {
        guard let elapsed else { return nil }
        guard isPlaying, let timestamp else { return elapsed }
        let rate = playbackRate > 0 ? playbackRate : 1
        let value = max(0, elapsed + date.timeIntervalSince(timestamp) * rate)
        return duration.map { min(value, $0) } ?? value
    }

    /// Identifie le morceau (pour savoir si on a changé de titre).
    var trackKey: String { "\(title)|\(artist ?? "")|\(album ?? "")" }
}

// MARK: - Source MediaRemote

extension NowPlayingInfo {
    /// Crée l'info à partir d'une charge utile de mediaremote-adapter (option `--micros`).
    /// Renvoie `nil` si aucun lecteur n'est actif.
    init?(mediaRemotePayload payload: [String: Any]) {
        guard let title = payload["title"] as? String, !title.isEmpty else { return nil }

        func seconds(_ key: String) -> TimeInterval? {
            guard let micros = payload[key] as? Double else { return nil }
            return micros / 1_000_000
        }

        self.origin = .mediaRemote
        self.title = title
        // Pour un lecteur intégré à une autre app, on préfère l'app « parente ».
        self.bundleIdentifier = payload["parentApplicationBundleIdentifier"] as? String
            ?? payload["bundleIdentifier"] as? String
        self.artist = (payload["artist"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.album = (payload["album"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.isPlaying = payload["playing"] as? Bool ?? false
        self.duration = seconds("durationMicros").flatMap { $0 > 0 ? $0 : nil }
        self.elapsed = seconds("elapsedTimeMicros")
        self.timestamp = seconds("timestampEpochMicros").map { Date(timeIntervalSince1970: $0) }
        self.playbackRate = payload["playbackRate"] as? Double ?? (isPlaying ? 1 : 0)

        if let base64 = payload["artworkData"] as? String,
           let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
            self.artwork = NSImage(data: data)
            var hasher = Hasher()
            hasher.combine(data)
            self.artworkHash = hasher.finalize()
        }
    }
}

// MARK: - Sources Music et Spotify (notifications publiques)

extension NowPlayingInfo {
    /// Notification « com.apple.Music.playerInfo ».
    init?(appleMusicUserInfo info: [AnyHashable: Any], now: Date = Date()) {
        guard let state = info["Player State"] as? String, state != "Stopped",
              let title = info["Name"] as? String, !title.isEmpty
        else { return nil }

        self.origin = .appleMusic
        self.bundleIdentifier = "com.apple.Music"
        self.title = title
        self.artist = info["Artist"] as? String
        self.album = info["Album"] as? String
        self.isPlaying = state == "Playing"
        // Music donne la durée en millisecondes, mais pas la position.
        self.duration = (info["Total Time"] as? Double).map { $0 / 1000 }
        self.receivedAt = now
    }

    /// Notification « com.spotify.client.PlaybackStateChanged ».
    init?(spotifyUserInfo info: [AnyHashable: Any], now: Date = Date()) {
        guard let state = info["Player State"] as? String, state != "Stopped",
              let title = info["Name"] as? String, !title.isEmpty
        else { return nil }

        self.origin = .spotify
        self.bundleIdentifier = "com.spotify.client"
        self.title = title
        self.artist = info["Artist"] as? String
        self.album = info["Album"] as? String
        self.isPlaying = state == "Playing"
        self.duration = (info["Duration"] as? Double).map { $0 / 1000 }
        self.elapsed = info["Playback Position"] as? Double
        self.timestamp = now
        self.receivedAt = now
    }
}

// MARK: - Choix de la source

enum NowPlayingArbiter {
    /// MediaRemote (toutes les apps) a la priorité ; sinon un lecteur public en cours de lecture,
    /// sinon le plus récent en pause.
    static func select(mediaRemote: NowPlayingInfo?, publicSources: [NowPlayingInfo]) -> NowPlayingInfo? {
        if let mediaRemote { return mediaRemote }
        if let playing = publicSources.filter(\.isPlaying).max(by: { $0.receivedAt < $1.receivedAt }) {
            return playing
        }
        return publicSources.max(by: { $0.receivedAt < $1.receivedAt })
    }
}
