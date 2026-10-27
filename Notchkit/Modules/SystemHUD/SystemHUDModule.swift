import AppKit
import SwiftUI
import Observation

/// État affiché par l'indicateur (mis à jour à chaque appui, sans recréer l'alerte).
@MainActor
@Observable
final class HUDState {
    enum Kind: Sendable {
        case volume
        case brightness
    }

    var kind: Kind = .volume
    var level: Float = 0
    var isMuted = false

    var symbol: String {
        switch kind {
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if isMuted || level == 0 { return "speaker.slash.fill" }
            if level < 0.34 { return "speaker.wave.1.fill" }
            if level < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }
}

/// Module Volume et luminosité : remplace l'indicateur de macOS par un affichage dans l'encoche.
///
/// Touches interceptées avec l'autorisation Accessibilité (event tap, API publique).
/// Volume : Core Audio (public). Luminosité de l'écran intégré : DisplayServices (⚠️ API privée).
@MainActor
@Observable
final class SystemHUDModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "systemhud",
        name: "Volume et luminosité",
        summary: "Remplace l'indicateur de volume et de luminosité de macOS par un affichage dans l'encoche.",
        systemImage: "speaker.wave.2",
        category: .system,
        tier: .free,
        defaultEnabled: true,
        backgroundEvents: true
    )

    let hud = HUDState()
    private(set) var isTrusted = MediaKeyTap.isTrusted
    private(set) var isIntercepting = false

    /// Remplacer l'indicateur de macOS (nécessite l'autorisation Accessibilité).
    var replaceSystemHUD: Bool {
        didSet {
            UserDefaults.standard.set(replaceSystemHUD, forKey: Keys.replaceSystemHUD)
            updateInterception()
        }
    }

    private enum Keys {
        static let replaceSystemHUD = "module.systemhud.replace"
    }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private let tap = MediaKeyTap()
    @ObservationIgnored private let volumeObserver = VolumeObserver()
    /// Volume et luminosité glissent vers leur nouveau niveau, comme avec macOS, au lieu de sauter.
    @ObservationIgnored private let volumeRamp = LevelRamp { SystemVolume.volume = $0 }
    @ObservationIgnored private let brightnessRamp = LevelRamp { DisplayBrightness.brightness = $0 }
    @ObservationIgnored private var trustPolling: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false
    /// Alerte unique, réaffichée à chaque appui (même identifiant : prolongée, pas recréée).
    @ObservationIgnored private lazy var alert: NotchAlert = {
        var alert = NotchAlert(
            leading: AnyView(HUDIcon(state: hud)),
            trailing: AnyView(HUDLevelBar(state: hud)),
            duration: .seconds(1.6)
        )
        // Survoler l'indicateur ouvre le centre du son.
        alert.openModuleID = Self.descriptor.id
        alert.sideWidth = NotchLayout.levelIndicatorSideWidth
        return alert
    }()

    /// Centre du son : appareils, volumes et apps qui jouent (actif seulement quand la carte est affichée).
    let audio = AudioCenter()

    init(context: ModuleContext) {
        self.context = context
        replaceSystemHUD = UserDefaults.standard.object(forKey: Keys.replaceSystemHUD) as? Bool ?? true
        audio.nowPlayingBundleID = { [weak self] in
            guard let info = (self?.context.otherModule(MusicModule.descriptor.id) as? MusicModule)?.nowPlaying,
                  info.isPlaying else { return nil }
            return info.bundleIdentifier
        }
    }

    // MARK: Cycle de vie

    func start() {
        guard !isStarted else { return }
        isStarted = true
        tap.handler = { [weak self] key, modifiers in self?.handle(key, modifiers: modifiers) ?? false }
        volumeObserver.onChange = { [weak self] in self?.volumeDidChange() }
        updateInterception()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        trustPolling?.cancel()
        trustPolling = nil
        tap.stop()
        volumeObserver.stop()
        isIntercepting = false
    }

    private func updateInterception() {
        isTrusted = MediaKeyTap.isTrusted
        guard isStarted, replaceSystemHUD, !AutomatedRun.isActive else {
            tap.stop()
            volumeObserver.stop()
            isIntercepting = false
            return
        }
        isIntercepting = tap.start()
        // Seulement quand les touches sont interceptées : sinon macOS affiche déjà son indicateur.
        if isIntercepting { volumeObserver.start() } else { volumeObserver.stop() }
    }

    /// Demande l'autorisation Accessibilité, puis surveille son obtention (toutes les 2 s, 2 min max).
    func requestAccessibility() {
        MediaKeyTap.requestTrust()
        MediaKeyTap.openAccessibilitySettings()
        trustPolling?.cancel()
        trustPolling = Task { [weak self] in
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                if MediaKeyTap.isTrusted {
                    self.updateInterception()
                    return
                }
            }
        }
    }

    // MARK: Touches

    /// Un cran = 1/16 (comme macOS) ; avec Maj + Option : 1/64.
    static func step(for modifiers: NSEvent.ModifierFlags) -> Float {
        modifiers.contains([.shift, .option]) ? 1 / 64 : 1 / 16
    }

    private func handle(_ key: MediaKey, modifiers: NSEvent.ModifierFlags) -> Bool {
        let step = Self.step(for: modifiers)
        switch key {
        case .volumeUp, .volumeDown:
            guard SystemVolume.isAdjustable else { return false }
            if SystemVolume.isMuted { SystemVolume.isMuted = false }
            // Appuis rapprochés : le cran part du niveau visé, pas du niveau atteint en cours de glissement.
            let current = volumeRamp.target ?? SystemVolume.volume
            let level = LevelRamp.clamped(current + (key == .volumeUp ? step : -step))
            volumeRamp.move(from: SystemVolume.volume, to: level)
            show(.volume, level: level, muted: level == 0)
            return true
        case .mute:
            guard SystemVolume.isAdjustable else { return false }
            SystemVolume.isMuted.toggle()
            show(.volume, level: SystemVolume.volume, muted: SystemVolume.isMuted)
            return true
        case .brightnessUp, .brightnessDown:
            guard DisplayBrightness.isAvailable, let current = DisplayBrightness.brightness else { return false }
            let level = LevelRamp.clamped((brightnessRamp.target ?? current) + (key == .brightnessUp ? step : -step))
            brightnessRamp.move(from: current, to: level)
            show(.brightness, level: level, muted: false)
            return true
        }
    }

    /// Volume changé hors du clavier (Touch Bar, Centre de contrôle…).
    private func volumeDidChange() {
        // Pendant le glissement lancé par une touche, les niveaux intermédiaires ne sont pas affichés.
        guard !volumeRamp.isRunning else { return }
        let level = SystemVolume.volume
        let muted = SystemVolume.isMuted || level == 0
        guard Self.isNewVolumeChange(shown: hud, level: level, muted: muted) else { return }
        // Pas de retour haptique : le curseur de la Touch Bar envoie des dizaines de changements.
        show(.volume, level: level, muted: muted, haptic: false)
    }

    /// Faux si l'indicateur affiche déjà ce volume (changement venu d'une touche déjà traitée).
    static func isNewVolumeChange(shown: HUDState, level: Float, muted: Bool) -> Bool {
        !(shown.kind == .volume && abs(shown.level - level) < 0.001 && shown.isMuted == muted)
    }

    private func show(_ kind: HUDState.Kind, level: Float, muted: Bool, haptic: Bool = true) {
        if haptic { Haptics.play(.step) }
        withAnimation(.snappy(duration: 0.15)) {
            hud.kind = kind
            hud.level = level
            hud.isMuted = muted
        }
        context.presentAlert(alert)
    }

    // MARK: Affichage

    var compactPriority: ModulePriority { .none }

    var expandedWidthWeight: CGFloat { 1.5 }

    func miniView() -> AnyView {
        AnyView(MiniWidget(symbol: SystemVolume.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                           value: "\(Int((SystemVolume.volume * 100).rounded())) %", caption: String(localized: "Volume")))
    }

    func expandedView() -> AnyView {
        AnyView(SystemHUDExpandedView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(SystemHUDSettingsView(module: self))
    }
}

#if DEBUG
extension SystemHUDModule {
    /// Affiche l'indicateur à un niveau donné, sans toucher au volume réel.
    func debugShow(_ kind: HUDState.Kind, level: Float) {
        hud.kind = kind
        hud.level = level
        hud.isMuted = false
        context.presentAlert(alert)
    }
}
#endif

/// Passage progressif d'un niveau à un autre (volume, luminosité) : macOS fait glisser le niveau
/// à chaque cran au lieu de le changer d'un coup. Chaque nouvel appui repart du niveau atteint.
@MainActor
final class LevelRamp {
    /// Durée d'un glissement.
    static let duration: TimeInterval = 0.2

    private let apply: (Float) -> Void
    /// Niveau visé pendant un glissement (`nil` au repos).
    private(set) var target: Float?
    private var start: Float = 0
    private var current: Float = 0
    private var startDate = Date()
    private var timer: Timer?

    var isRunning: Bool { timer != nil }

    init(apply: @escaping (Float) -> Void) {
        self.apply = apply
    }

    nonisolated static func clamped(_ level: Float) -> Float { min(1, max(0, level)) }

    /// Niveau après la fraction `progress` (0…1) du glissement, avec ralentissement à l'arrivée.
    nonisolated static func value(from start: Float, to end: Float, progress: Double) -> Float {
        let t = Float(min(1, max(0, progress)))
        let eased = 1 - (1 - t) * (1 - t)
        return start + (end - start) * eased
    }

    func move(from level: Float, to newTarget: Float) {
        start = isRunning ? current : level
        current = start
        target = newTarget
        startDate = Date()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let target else { return }
        let progress = Date().timeIntervalSince(startDate) / Self.duration
        current = Self.value(from: start, to: target, progress: progress)
        apply(current)
        if progress >= 1 {
            timer?.invalidate()
            timer = nil
            self.target = nil
        }
    }
}
