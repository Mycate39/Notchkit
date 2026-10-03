import Foundation
import IOKit.ps
import Testing
@testable import Notchkit

struct BatteryStateTests {
    /// Description IOKit telle que macOS la fournit pour une batterie interne.
    func description(
        current: Int = 78, max: Int = 100, charging: Bool = false, charged: Bool = false,
        source: String = kIOPSBatteryPowerValue, toEmpty: Int = 185, toFull: Int = -1,
        type: String = kIOPSInternalBatteryType
    ) -> [String: Any] {
        [
            kIOPSTypeKey: type,
            kIOPSCurrentCapacityKey: current,
            kIOPSMaxCapacityKey: max,
            kIOPSIsChargingKey: charging,
            kIOPSIsChargedKey: charged,
            kIOPSPowerSourceStateKey: source,
            kIOPSTimeToEmptyKey: toEmpty,
            kIOPSTimeToFullChargeKey: toFull,
        ]
    }

    @Test func lectureSurBatterie() throws {
        let state = try #require(BatteryState(description: description()))
        #expect(state.level == 78)
        #expect(state.status == .discharging)
        #expect(state.minutesToEmpty == 185)
        #expect(state.minutesToFull == nil)
        #expect(!state.isLow)
    }

    @Test func lectureEnCharge() throws {
        let state = try #require(BatteryState(description: description(
            current: 40, charging: true, source: kIOPSACPowerValue, toEmpty: 0, toFull: 72
        )))
        #expect(state.status == .charging)
        #expect(state.minutesToFull == 72)
        #expect(state.minutesToEmpty == nil)
    }

    @Test func calculEnCoursDonneNil() throws {
        let state = try #require(BatteryState(description: description(toEmpty: -1)))
        #expect(state.minutesToEmpty == nil)
    }

    @Test func brancheeEtPleineOuEnPause() throws {
        let full = try #require(BatteryState(description: description(current: 100, charged: true, source: kIOPSACPowerValue)))
        #expect(full.status == .charged)
        let paused = try #require(BatteryState(description: description(current: 80, source: kIOPSACPowerValue)))
        #expect(paused.status == .pluggedNotCharging)
    }

    @Test func capaciteNonEnPourcentage() throws {
        // Certains Mac renvoient la capacité en mAh : le niveau est recalculé en pourcentage.
        let state = try #require(BatteryState(description: description(current: 3285, max: 3294)))
        #expect(state.level == 100)
    }

    @Test func ignoreLesSourcesQuiNeSontPasUneBatterieInterne() {
        #expect(BatteryState(description: description(type: kIOPSUPSType)) == nil)
        #expect(BatteryState(description: [kIOPSTypeKey: kIOPSInternalBatteryType]) == nil)
    }
}

struct BatteryEventDetectorTests {
    func state(_ level: Int, plugged: Bool) -> BatteryState {
        BatteryState(level: level, isCharging: plugged, isCharged: false, powerSource: plugged ? .ac : .battery)
    }

    @Test func pasDAlerteAuPremierReleve() {
        var detector = BatteryEventDetector()
        #expect(detector.process(from: nil, to: state(80, plugged: true)) == nil)
    }

    @Test func brancherEtDebrancher() {
        var detector = BatteryEventDetector()
        #expect(detector.process(from: state(80, plugged: false), to: state(80, plugged: true)) == .pluggedIn)
        #expect(detector.process(from: state(80, plugged: true), to: state(80, plugged: false)) == .unplugged)
    }

    @Test func seuilsDeBatterieFaibleSignalesUneSeuleFois() {
        var detector = BatteryEventDetector()
        #expect(detector.process(from: state(22, plugged: false), to: state(21, plugged: false)) == nil)
        #expect(detector.process(from: state(21, plugged: false), to: state(20, plugged: false)) == .low(threshold: 20))
        #expect(detector.process(from: state(20, plugged: false), to: state(19, plugged: false)) == nil)
        #expect(detector.process(from: state(11, plugged: false), to: state(10, plugged: false)) == .low(threshold: 10))
        #expect(detector.process(from: state(10, plugged: false), to: state(9, plugged: false)) == nil)
    }

    @Test func rebrancherReinitialiseLesSeuils() {
        var detector = BatteryEventDetector()
        _ = detector.process(from: state(21, plugged: false), to: state(20, plugged: false))
        _ = detector.process(from: state(20, plugged: false), to: state(20, plugged: true))
        #expect(detector.process(from: state(20, plugged: true), to: state(20, plugged: false)) == .unplugged)
        #expect(detector.process(from: state(20, plugged: false), to: state(19, plugged: false)) == .low(threshold: 20))
    }

    @Test func lancementAvecBatterieDejaTresFaible() {
        // Au démarrage à 8 % : une seule alerte (10 %), pas deux.
        var detector = BatteryEventDetector()
        #expect(detector.process(from: nil, to: state(8, plugged: false)) == .low(threshold: 10))
        #expect(detector.process(from: state(8, plugged: false), to: state(7, plugged: false)) == nil)
    }
}
