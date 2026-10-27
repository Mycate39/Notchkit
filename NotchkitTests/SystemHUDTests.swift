import AppKit
import Testing
@testable import Notchkit

struct MediaKeyTests {
    /// data1 = code de touche << 16 | état << 8 | répétition.
    func data1(_ keyCode: Int, down: Bool, repeat isRepeat: Bool = false) -> Int {
        (keyCode << 16) | ((down ? 0x0A : 0x0B) << 8) | (isRepeat ? 1 : 0)
    }

    @Test func decodageDesTouches() {
        #expect(MediaKey.decode(data1: data1(0, down: true))?.key == .volumeUp)
        #expect(MediaKey.decode(data1: data1(1, down: true))?.isDown == true)
        #expect(MediaKey.decode(data1: data1(7, down: false))?.isDown == false)
        #expect(MediaKey.decode(data1: data1(3, down: true, repeat: true))?.isRepeat == true)
        #expect(MediaKey.decode(data1: data1(16, down: true)) == nil) // lecture/pause : non géré ici
    }

    @Test @MainActor func pasDeReglageFin() {
        #expect(SystemHUDModule.step(for: []) == Float(1) / 16)
        #expect(SystemHUDModule.step(for: [.shift, .option]) == Float(1) / 64)
    }

    @Test @MainActor func iconeSelonLeNiveau() {
        let state = HUDState()
        state.level = 0.9
        #expect(state.symbol == "speaker.wave.3.fill")
        state.isMuted = true
        #expect(state.symbol == "speaker.slash.fill")
        state.kind = .brightness
        state.level = 0.2
        #expect(state.symbol == "sun.min.fill")
    }

    @Test @MainActor func alertesALaLargeurDeLaMusique() {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "notchkit.tests.\(UUID().uuidString)")!)
        let manager = ModuleManager(settings: settings, entitlements: EntitlementManager(), availableModules: [])
        let viewModel = NotchViewModel(manager: manager, settings: settings)
        viewModel.present(NotchAlert(duration: .seconds(5)))
        #expect(viewModel.compactSideWidth == NotchLayout.activitySideWidth)
        #expect(NotchLayout.compactSideWidth == NotchLayout.activitySideWidth)
    }

    @Test @MainActor func indicateurDeVolumePlusLarge() {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "notchkit.tests.\(UUID().uuidString)")!)
        let manager = ModuleManager(settings: settings, entitlements: EntitlementManager(), availableModules: [])
        let viewModel = NotchViewModel(manager: manager, settings: settings)
        var alert = NotchAlert(duration: .seconds(5))
        alert.sideWidth = NotchLayout.levelIndicatorSideWidth
        viewModel.present(alert)
        #expect(viewModel.compactSideWidth == NotchLayout.levelIndicatorSideWidth)
        #expect(NotchLayout.levelIndicatorSideWidth > NotchLayout.activitySideWidth)
    }
}

@MainActor
struct VolumeTouchBarTests {
    func state(_ kind: HUDState.Kind, level: Float, muted: Bool) -> HUDState {
        let hud = HUDState()
        hud.kind = kind
        hud.level = level
        hud.isMuted = muted
        return hud
    }

    @Test func changementDejaAfficheParUneToucheIgnore() {
        #expect(!SystemHUDModule.isNewVolumeChange(shown: state(.volume, level: 0.5, muted: false), level: 0.5, muted: false))
    }

    @Test func changementVenuDeLaTouchBarAffiche() {
        #expect(SystemHUDModule.isNewVolumeChange(shown: state(.volume, level: 0.5, muted: false), level: 0.56, muted: false))
        #expect(SystemHUDModule.isNewVolumeChange(shown: state(.volume, level: 0.5, muted: false), level: 0.5, muted: true))
    }

    @Test func apresLaLuminositeLeVolumeSAffiche() {
        #expect(SystemHUDModule.isNewVolumeChange(shown: state(.brightness, level: 0.5, muted: false), level: 0.5, muted: false))
    }
}

struct LevelRampTests {
    @Test func glissementProgressifJusquAuNiveauVise() {
        #expect(LevelRamp.value(from: 0.5, to: 0.5625, progress: 0) == 0.5)
        #expect(LevelRamp.value(from: 0.5, to: 0.5625, progress: 1) == 0.5625)
        let middle = LevelRamp.value(from: 0, to: 1, progress: 0.5)
        // Ralentit à l'arrivée : plus de la moitié du chemin à mi-temps, sans dépasser.
        #expect(middle > 0.5 && middle < 1)
        #expect(LevelRamp.value(from: 0, to: 1, progress: 2) == 1)
        #expect(LevelRamp.clamped(1.06) == 1 && LevelRamp.clamped(-0.06) == 0)
    }
}
