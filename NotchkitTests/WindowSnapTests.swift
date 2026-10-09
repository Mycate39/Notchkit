import CoreGraphics
import Testing
@testable import Notchkit

struct SnapZoneTests {
    // Écran 1440×900, barre des menus de 25 pt : zone utile 1440×875 (origine AppKit en bas).
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func moitieGaucheEtQuartBasDroit() {
        #expect(SnapZone.leftHalf.frame(visibleFrame: visible, primaryHeight: 900) == CGRect(x: 0, y: 25, width: 720, height: 875))
        #expect(SnapZone.bottomRight.frame(visibleFrame: visible, primaryHeight: 900)
                == CGRect(x: 720, y: 463, width: 720, height: 438))
        #expect(SnapZone.centerThird.frame(visibleFrame: visible, primaryHeight: 900).minX == 480)
    }

    @Test func declenchementPresDuHaut() {
        #expect(SnapZone.isNearTop(pointerY: 880, screenMaxY: 900))
        #expect(!SnapZone.isNearTop(pointerY: 700, screenMaxY: 900))
    }

    @Test func tuileSousLePointeur() {
        let panel = SnapLayout.panelFrame(screen: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let frames = SnapLayout.tileFrames(panel: panel)
        #expect(frames.count == SnapZone.allCases.count)
        let maximize = try! #require(frames[.maximize])
        #expect(SnapLayout.zone(at: CGPoint(x: maximize.midX, y: maximize.midY), panel: panel) == .maximize)
        #expect(SnapLayout.zone(at: CGPoint(x: 5, y: 5), panel: panel) == nil)
        #expect(panel.maxY == 900 - SnapLayout.topOffset)
    }
}
