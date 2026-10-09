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

    @Test func alerteLargeElargitLEncoche() {
        let geometry = NotchGeometry(style: .notch, closedSize: CGSize(width: 185, height: 32), screenFrame: .zero, centerX: 0)
        let normal = NotchLayout.shapeSize(for: geometry, isExpanded: false, hasCompactContent: true)
        let wide = NotchLayout.shapeSize(for: geometry, isExpanded: false, hasCompactContent: true, sideWidth: 112)
        #expect(wide.width - normal.width == (112 - NotchLayout.compactSideWidth) * 2)
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
