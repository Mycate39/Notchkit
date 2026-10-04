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
        defaultEnabled: true
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
    @ObservationIgnored private var trustPolling: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false
    /// Alerte unique, réaffichée à chaque appui (même identifiant : prolongée, pas recréée).
    @ObservationIgnored private lazy var alert = NotchAlert(
        leading: AnyView(HUDIcon(state: hud)),
        trailing: AnyView(HUDLevelBar(state: hud)),
        duration: .seconds(1.6),
        sideWidth: 112
    )

    init(context: ModuleContext) {
        self.context = context
        replaceSystemHUD = UserDefaults.standard.object(forKey: Keys.replaceSystemHUD) as? Bool ?? true
    }

    // MARK: Cycle de vie

    func start() {
        guard !isStarted else { return }
        isStarted = true
        tap.handler = { [weak self] key, modifiers in self?.handle(key, modifiers: modifiers) ?? false }
        updateInterception()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        trustPolling?.cancel()
        trustPolling = nil
        tap.stop()
        isIntercepting = false
    }

    private func updateInterception() {
        isTrusted = MediaKeyTap.isTrusted
        guard isStarted, replaceSystemHUD, !AutomatedRun.isActive else {
            tap.stop()
            isIntercepting = false
            return
        }
        isIntercepting = tap.start()
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
            SystemVolume.volume += key == .volumeUp ? step : -step
            show(.volume, level: SystemVolume.volume, muted: SystemVolume.volume == 0)
            return true
        case .mute:
            guard SystemVolume.isAdjustable else { return false }
            SystemVolume.isMuted.toggle()
            show(.volume, level: SystemVolume.volume, muted: SystemVolume.isMuted)
            return true
        case .brightnessUp, .brightnessDown:
            guard DisplayBrightness.isAvailable, let current = DisplayBrightness.brightness else { return false }
            DisplayBrightness.brightness = current + (key == .brightnessUp ? step : -step)
            show(.brightness, level: DisplayBrightness.brightness ?? current, muted: false)
            return true
        }
    }

    private func show(_ kind: HUDState.Kind, level: Float, muted: Bool) {
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
