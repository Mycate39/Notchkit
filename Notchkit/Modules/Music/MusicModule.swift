import AppKit
import SwiftUI
import Observation

/// Module Musique : morceau en cours, pochette et commandes de lecture.
///
/// Deux niveaux de sources :
/// - « Toutes les apps » (MediaRemoteSource, API privée, activée par défaut) : Deezer,
///   navigateurs, Spotify, Music… ;
/// - Music et Spotify en API publiques, toujours actives, qui prennent le relais
///   si la première ne renvoie rien (désactivée ou cassée par une mise à jour de macOS).
@MainActor
@Observable
final class MusicModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "music",
        name: "Musique",
        summary: "Morceau en cours et commandes de lecture (Deezer, Spotify, Music, navigateurs…).",
        systemImage: "music.note",
        category: .media,
        tier: .free,
        defaultEnabled: true
    )

    private(set) var nowPlaying: NowPlayingInfo?

    // MARK: Réglages du module

    /// Affiche la pochette et l'égaliseur quand l'encoche est repliée et qu'un morceau joue.
    var showInCompact: Bool {
        didSet { UserDefaults.standard.set(showInCompact, forKey: Keys.showInCompact) }
    }
    /// Utilise la source « Toutes les apps » (MediaRemote, API privée).
    var useMediaRemote: Bool {
        didSet {
            UserDefaults.standard.set(useMediaRemote, forKey: Keys.useMediaRemote)
            guard isStarted, useMediaRemote != oldValue else { return }
            useMediaRemote ? mediaRemote.start() : mediaRemote.stop()
        }
    }

    private enum Keys {
        static let showInCompact = "module.music.showInCompact"
        static let useMediaRemote = "module.music.useMediaRemote"
    }

    // MARK: Sources

    @ObservationIgnored private let mediaRemote = MediaRemoteSource()
    @ObservationIgnored private let publicSources: [NowPlayingInfo.Origin: ScriptablePlayerSource] = [
        .appleMusic: ScriptablePlayerSource(player: ScriptablePlayerSource.appleMusic),
        .spotify: ScriptablePlayerSource(player: ScriptablePlayerSource.spotify),
    ]
    @ObservationIgnored private var mediaRemoteInfo: NowPlayingInfo?
    @ObservationIgnored private var publicInfos: [NowPlayingInfo.Origin: NowPlayingInfo] = [:]
    @ObservationIgnored private var isStarted = false

    init(context: ModuleContext) {
        let defaults = UserDefaults.standard
        showInCompact = defaults.object(forKey: Keys.showInCompact) as? Bool ?? true
        useMediaRemote = defaults.object(forKey: Keys.useMediaRemote) as? Bool ?? true
    }

    // MARK: Cycle de vie

    func start() {
        guard !isStarted else { return }
        isStarted = true

        mediaRemote.onUpdate = { [weak self] info in
            self?.mediaRemoteInfo = info
            self?.updateSelection()
        }
        if useMediaRemote { mediaRemote.start() }

        for (origin, source) in publicSources {
            source.onUpdate = { [weak self] info in
                self?.publicInfos[origin] = info
                self?.updateSelection()
            }
            source.start()
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        mediaRemote.stop()
        publicSources.values.forEach { $0.stop() }
        mediaRemoteInfo = nil
        publicInfos.removeAll()
        nowPlaying = nil
    }

    private func updateSelection() {
        nowPlaying = NowPlayingArbiter.select(
            mediaRemote: useMediaRemote ? mediaRemoteInfo : nil,
            publicSources: Array(publicInfos.values)
        )
    }

    // MARK: Commandes

    func send(_ command: PlaybackCommand) {
        guard let current = nowPlaying else { return }
        switch current.origin {
        case .mediaRemote: mediaRemote.send(command)
        case .appleMusic, .spotify: publicSources[current.origin]?.send(command)
        }
        // Retour visuel immédiat ; la source confirmera (ou corrigera) dans un instant.
        if command == .togglePlayPause {
            nowPlaying?.elapsed = current.elapsed(at: Date())
            nowPlaying?.timestamp = Date()
            nowPlaying?.isPlaying.toggle()
        }
    }

    /// Met au premier plan l'app qui joue.
    func openPlayerApp() {
        guard let bundleID = nowPlaying?.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Affichage

    var compactPriority: ModulePriority {
        showInCompact && nowPlaying?.isPlaying == true ? .normal : .none
    }

    var expandedWidthWeight: CGFloat { 2 }

    func compactLeading() -> AnyView? {
        guard let nowPlaying else { return nil }
        return AnyView(ArtworkView(info: nowPlaying, size: 20, cornerRadius: 5))
    }

    func compactTrailing() -> AnyView? {
        guard let nowPlaying else { return nil }
        return AnyView(
            EqualizerView(isAnimating: nowPlaying.isPlaying)
                .frame(width: 18, height: 14)
        )
    }

    func expandedView() -> AnyView {
        AnyView(MusicExpandedView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(MusicSettingsView(module: self))
    }
}
