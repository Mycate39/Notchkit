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

struct ChargeTimeTests {
    func charging(_ level: Int, minutes: Int?) -> BatteryState {
        BatteryState(level: level, isCharging: true, isCharged: false, powerSource: .ac, minutesToFull: minutes)
    }

    @Test func formatCourtDuTempsDeCharge() {
        #expect(ChargeTimeFormat.compact(minutes: 45) == "45 min")
        #expect(ChargeTimeFormat.compact(minutes: 0) == "1 min")
        #expect(ChargeTimeFormat.compact(minutes: 65) == "1 h 05")
        #expect(ChargeTimeFormat.compact(minutes: 120) == "2 h")
    }

    @Test func heurePrevueDeLaChargeComplete() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(charging(50, minutes: 90).estimatedFullDate(from: now) == now.addingTimeInterval(5400))
        // Estimation en cours ou charge en pause : pas d'heure.
        #expect(charging(50, minutes: nil).estimatedFullDate(from: now) == nil)
        let paused = BatteryState(level: 80, isCharging: false, isCharged: false, powerSource: .ac, minutesToFull: nil)
        #expect(paused.estimatedFullDate(from: now) == nil)
    }

    @Test @MainActor func activiteDeChargeSeulementPendantLaCharge() {
        func priority(_ state: BatteryState?, activity: Bool = true, permanent: Bool = false) -> ModulePriority {
            BatteryModule.compactPriority(for: state, showInCompact: permanent, lowBatteryAlert: true,
                                          chargingActivity: activity)
        }
        #expect(priority(charging(40, minutes: 50)) == .normal)
        // Réglage coupé : seulement le niveau permanent, s'il est demandé.
        #expect(priority(charging(40, minutes: 50), activity: false) == .none)
        #expect(priority(charging(40, minutes: 50), activity: false, permanent: true) == .low)
        // Pleine ou en pause : plus d'activité.
        #expect(priority(BatteryState(level: 100, isCharging: false, isCharged: true, powerSource: .ac)) == .none)
        #expect(priority(BatteryState(level: 80, isCharging: false, isCharged: false, powerSource: .ac)) == .none)
        // Batterie très faible : toujours affichée.
        #expect(priority(BatteryState(level: 8, isCharging: false, isCharged: false, powerSource: .battery)) == .normal)
        #expect(priority(nil) == .none)
    }
}
