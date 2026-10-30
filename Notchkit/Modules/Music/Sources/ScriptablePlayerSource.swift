import Foundation

/// Source publique pour Music ou Spotify.
///
/// - Informations : notifications diffusées par l'app à chaque changement de morceau ou
///   d'état (aucune autorisation nécessaire, aucun relevé périodique).
/// - Commandes : AppleScript. macOS demande l'autorisation à la première commande.
@MainActor
final class ScriptablePlayerSource {
    struct Player: Sendable {
        let bundleIdentifier: String
        let notificationName: String
        let parse: @Sendable ([AnyHashable: Any]) -> NowPlayingInfo?
    }

    static let appleMusic = Player(
        bundleIdentifier: "com.apple.Music",
        notificationName: "com.apple.Music.playerInfo",
        parse: { NowPlayingInfo(appleMusicUserInfo: $0) }
    )

    static let spotify = Player(
        bundleIdentifier: "com.spotify.client",
        notificationName: "com.spotify.client.PlaybackStateChanged",
        parse: { NowPlayingInfo(spotifyUserInfo: $0) }
    )

    let player: Player
    var onUpdate: (@MainActor (NowPlayingInfo?) -> Void)?
    private var observer: NSObjectProtocol?

    init(player: Player) {
        self.player = player
    }

    func start() {
        guard observer == nil else { return }
        let parse = player.parse
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(player.notificationName),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let info = notification.userInfo.flatMap(parse)
            MainActor.assumeIsolated { self?.onUpdate?(info) }
        }
    }

    func stop() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observer = nil
        onUpdate?(nil)
    }

    func send(_ command: PlaybackCommand) {
        let verb = switch command {
        case .togglePlayPause: "playpause"
        case .nextTrack: "next track"
        case .previousTrack: "previous track"
        case let .seek(position): "set player position to \(max(0, position))"
        // Music et Spotify n'ont pas le même vocabulaire pour l'aléatoire et la répétition.
        case .toggleShuffle: player.bundleIdentifier == "com.spotify.client"
            ? "set shuffling to not shuffling" : "set shuffle enabled to not shuffle enabled"
        case .toggleRepeat: player.bundleIdentifier == "com.spotify.client"
            ? "set repeating to not repeating"
            : "if song repeat is off then\nset song repeat to all\nelse\nset song repeat to off\nend if"
        }
        let source = "tell application id \"\(player.bundleIdentifier)\"\n\(verb)\nend tell"
        // AppleScript est bloquant : on l'exécute hors du thread principal.
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }
}
