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

    /// Affiche la petite icône de l'app qui joue (ex. Brave) sur la pochette.
    var showAppBadge: Bool {
        didSet { UserDefaults.standard.set(showAppBadge, forKey: Keys.showAppBadge) }
    }

    /// Barres de l'égaliseur qui suivent le son en temps réel (capture du son du système).
    var reactiveEqualizer: Bool {
        didSet {
            UserDefaults.standard.set(reactiveEqualizer, forKey: Keys.reactiveEqualizer)
            updateSpectrumCapture()
        }
    }

    /// Analyse du son pour l'égaliseur en temps réel.
    let spectrum = AudioSpectrumMonitor()

    private enum Keys {
        static let reactiveEqualizer = "module.music.reactiveEqualizer"
        static let showAppBadge = "module.music.showAppBadge"
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
    /// Dernier morceau d'un lecteur qui a quitté MediaRemote en pause (voir `resumesInApp`).
    @ObservationIgnored private var retainedInfo: NowPlayingInfo?
    @ObservationIgnored private var retainedExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    /// Au-delà, le morceau retenu est oublié (onglet fermé, écoute abandonnée).
    private static let retainedLifetime: Duration = .seconds(30 * 60)
    @ObservationIgnored private var publicInfos: [NowPlayingInfo.Origin: NowPlayingInfo] = [:]
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var spectrumStopTask: Task<Void, Never>?

    init(context: ModuleContext) {
        let defaults = UserDefaults.standard
        showInCompact = defaults.object(forKey: Keys.showInCompact) as? Bool ?? true
        useMediaRemote = defaults.object(forKey: Keys.useMediaRemote) as? Bool ?? true
        showAppBadge = defaults.object(forKey: Keys.showAppBadge) as? Bool ?? true
        reactiveEqualizer = defaults.object(forKey: Keys.reactiveEqualizer) as? Bool ?? true
    }

    // MARK: Cycle de vie

    func start() {
        guard !isStarted else { return }
        isStarted = true

        mediaRemote.onUpdate = { [weak self] info in
            self?.mediaRemoteChanged(info)
        }
        // App du morceau retenu quittée : plus rien à reprendre.
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, bundleID != nil, bundleID == self.retainedInfo?.bundleIdentifier else { return }
                self.forgetRetained()
                self.updateSelection()
            }
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
        forgetRetained()
        terminationObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
        terminationObserver = nil
        publicInfos.removeAll()
        nowPlaying = nil
        spectrumStopTask?.cancel()
        spectrum.stop()
    }

    /// Certains lecteurs (navigateurs) quittent MediaRemote dès qu'on les met en pause : on garde
    /// leur dernier morceau, en pause, pour pouvoir le reprendre depuis l'encoche.
    private func mediaRemoteChanged(_ info: NowPlayingInfo?) {
        if info == nil, let previous = mediaRemoteInfo {
            retainedInfo = previous.retainedAfterDisappearing(at: Date())
            retainedExpiryTask?.cancel()
            retainedExpiryTask = Task { [weak self] in
                try? await Task.sleep(for: Self.retainedLifetime)
                guard !Task.isCancelled, let self else { return }
                self.forgetRetained()
                self.updateSelection()
            }
        } else if info != nil {
            forgetRetained()
        }
        mediaRemoteInfo = info
        updateSelection()
    }

    private func forgetRetained() {
        retainedInfo = nil
        retainedExpiryTask?.cancel()
        retainedExpiryTask = nil
    }

    private func updateSelection() {
        #if DEBUG
        guard !debugPinned else { return }
        #endif
        nowPlaying = NowPlayingArbiter.select(
            mediaRemote: useMediaRemote ? mediaRemoteInfo : nil,
            retained: useMediaRemote ? retainedInfo : nil,
            publicSources: Array(publicInfos.values)
        )
        updateSpectrumCapture()
    }

    /// La capture du son ne tourne que pendant la lecture. Après une pause, on attend
    /// quelques secondes avant de l'arrêter (changement de morceau, pause brève).
    private func updateSpectrumCapture() {
        let shouldRun = isStarted && reactiveEqualizer && nowPlaying?.isPlaying == true
            && !Self.isStressTest
        if shouldRun {
            spectrumStopTask?.cancel()
            spectrumStopTask = nil
            spectrum.start()
        } else if spectrum.isRunning, spectrumStopTask == nil {
            let delay: Duration = reactiveEqualizer && isStarted ? .seconds(5) : .zero
            spectrumStopTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                self.spectrumStopTask = nil
                self.spectrum.stop()
            }
        }
    }

    /// Les lancements automatisés (test de charge, captures d'écran) ne doivent pas déclencher
    /// de demande d'autorisation audio.
    private static var isStressTest: Bool { AutomatedRun.isActive && !AutomatedRun.isDiagnostic }

    // MARK: Commandes

    func send(_ command: PlaybackCommand) {
        guard let current = nowPlaying else { return }
        // Lecteur sorti de MediaRemote : aucune commande ne l'atteint, on ouvre son app.
        if current.resumesInApp {
            openPlayerApp()
            return
        }
        if !isDemoTrack {
            switch current.origin {
            case .mediaRemote: mediaRemote.send(command)
            case .appleMusic, .spotify: publicSources[current.origin]?.send(command)
            }
        }
        // Retour visuel immédiat ; la source confirmera (ou corrigera) dans un instant.
        if command == .togglePlayPause {
            nowPlaying?.elapsed = current.elapsed(at: Date())
            nowPlaying?.timestamp = Date()
            nowPlaying?.isPlaying.toggle()
            updateSpectrumCapture()
        }
        if case let .seek(position) = command {
            nowPlaying?.elapsed = position
            nowPlaying?.timestamp = Date()
        }
    }

    /// Morceau fictif d'un tournage de démonstration : les commandes n'atteignent aucun vrai lecteur.
    private var isDemoTrack: Bool {
        #if DEBUG
        debugPinned
        #else
        false
        #endif
    }

    /// Met au premier plan l'app qui joue.
    func openPlayerApp() {
        guard let bundleID = nowPlaying?.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    #if DEBUG
    /// Outil de captures : affiche un morceau fictif.
    func debugSetNowPlaying(_ info: NowPlayingInfo?) {
        nowPlaying = info
    }

    @ObservationIgnored private var debugPinned = false

    /// Tournage de démonstration : morceau imposé (ou aucun), les vraies sources sont ignorées.
    func debugPinNowPlaying(_ info: NowPlayingInfo?) {
        debugPinned = true
        nowPlaying = info
        updateSpectrumCapture()
    }

    /// Fin du tournage : les vraies sources reprennent la main.
    func debugUnpin() {
        debugPinned = false
        updateSelection()
    }
    #endif

    // MARK: Affichage

    /// Grand lecteur de l'écran verrouillé : grande pochette, ou pochette rentrée dans le panneau (clic
    /// sur la pochette). Gardé ici pour survivre aux mises à jour de la fenêtre du lecteur.
    var lockScreenArtworkExpanded = true

    /// En lecture, la musique passe devant les autres activités en cours (`media`).
    var compactPriority: ModulePriority {
        showInCompact && nowPlaying?.isPlaying == true ? .media : .none
    }

    /// En pause, la bulle reste (pour relancer la lecture depuis ses commandes) ; en lecture, elle
    /// passe en tête des bulles.
    var bubblePriority: ModulePriority {
        guard showInCompact, let nowPlaying else { return .none }
        return nowPlaying.isPlaying ? .media : .normal
    }

    /// Contour teinté par la pochette (gris clair sans pochette).
    var keyLineColor: Color? {
        guard let nowPlaying else { return nil }
        let tint = ArtworkTint.color(for: nowPlaying)
        return tint == .white ? nil : Color(nsColor: tint)
    }

    var expandedWidthWeight: CGFloat { 2 }

    /// Affichage replié façon Dynamic Island : pochette à gauche, barres teintées à droite.
    var compactIsland: Bool { true }


    func compactLeading() -> AnyView? {
        guard let nowPlaying else { return nil }
        return AnyView(IslandArtworkView(info: nowPlaying))
    }

    func compactTrailing() -> AnyView? {
        guard let nowPlaying else { return nil }
        return AnyView(
            EqualizerView(isAnimating: nowPlaying.isPlaying, monitor: reactiveEqualizer ? spectrum : nil,
                          color: ArtworkTint.color(for: nowPlaying), spacingRatio: 1, bellShaped: true)
                .frame(width: 26)
                .padding(.vertical, 1)
        )
    }

    func bubbleControls() -> AnyView? {
        guard let nowPlaying else { return nil }
        return AnyView(BubblePlaybackControls(module: self, isPlaying: nowPlaying.isPlaying))
    }

    func expandedView() -> AnyView {
        AnyView(MusicExpandedView(module: self))
    }

    func miniView() -> AnyView {
        AnyView(MusicMiniView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(MusicSettingsView(module: self))
    }
}
