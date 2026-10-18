import Foundation
import Testing
@testable import Notchkit

/// Mouvements de la mascotte : fonctions pures du temps.
struct MascotMotionTests {
    @Test func clignementBrefEtRegulier() {
        // Yeux ouverts la plupart du temps, fermés au milieu du clignement.
        #expect(MascotMotion.blink(at: 1) == 0)
        let middle = MascotMotion.blinkInterval - MascotMotion.blinkDuration / 2
        #expect(MascotMotion.blink(at: middle) > 0.99)
        #expect(MascotMotion.blink(at: middle + MascotMotion.blinkInterval) > 0.99)
    }

    @Test func sautDeJoieMonteEtRetombe() {
        // Au milieu du saut, la mascotte est en l'air ; entre deux sauts, au sol.
        #expect(MascotMotion.pose(at: 0.3, mood: .happy).lift < -0.19)
        #expect(MascotMotion.pose(at: 1.0, mood: .happy).lift == 0)
    }

    @Test func colereTrembleParSalves() {
        let shaking = (0..<20).map { MascotMotion.pose(at: Double($0) * 0.01 + 0.02, mood: .angry).tilt }
        #expect(shaking.contains { abs($0) > 2 })
        // Hors salve, la mascotte est immobile.
        #expect(MascotMotion.pose(at: 1.0, mood: .angry).tilt == 0)
    }

    @Test func memeInstantMemePosture() {
        for mood in MascotMood.allCases {
            #expect(MascotMotion.pose(at: 2.345, mood: mood) == MascotMotion.pose(at: 2.345, mood: mood))
        }
    }
}
