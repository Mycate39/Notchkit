import SwiftUI
import Observation

/// Module Batterie : niveau, état de charge, autonomie, mode économie d'énergie,
/// et alertes au branchement, au débranchement et en cas de batterie faible.
@MainActor
@Observable
final class BatteryModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "battery",
        name: "Batterie",
        summary: "Niveau, état de charge et animation au branchement.",
        systemImage: "battery.75percent",
        category: .system,
        tier: .free,
        defaultEnabled: true
    )

    /// `nil` si le Mac n'a pas de batterie (Mac de bureau).
    private(set) var state: BatteryState?
    private(set) var isLowPowerMode = false

    // MARK: Réglages du module

    /// Affiche en permanence le niveau quand l'encoche est repliée.
    var showInCompact: Bool {
        didSet { UserDefaults.standard.set(showInCompact, forKey: Keys.showInCompact) }
    }
    /// Animation au branchement et au débranchement du chargeur.
    var alertOnPowerChange: Bool {
        didSet { UserDefaults.standard.set(alertOnPowerChange, forKey: Keys.alertOnPowerChange) }
    }
    /// Alerte à 20 % et 10 %, et indicateur permanent sous 10 %.
    var lowBatteryAlert: Bool {
        didSet { UserDefaults.standard.set(lowBatteryAlert, forKey: Keys.lowBatteryAlert) }
    }

    private enum Keys {
        static let showInCompact = "module.battery.showInCompact"
        static let alertOnPowerChange = "module.battery.alertOnPowerChange"
        static let lowBatteryAlert = "module.battery.lowBatteryAlert"
    }

    // MARK: Privé

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var monitor: PowerSourceMonitor?
    @ObservationIgnored private var lowPowerObserver: NSObjectProtocol?
    @ObservationIgnored private var detector = BatteryEventDetector()

    init(context: ModuleContext) {
        self.context = context
        let defaults = UserDefaults.standard
        showInCompact = defaults.object(forKey: Keys.showInCompact) as? Bool ?? false
        alertOnPowerChange = defaults.object(forKey: Keys.alertOnPowerChange) as? Bool ?? true
        lowBatteryAlert = defaults.object(forKey: Keys.lowBatteryAlert) as? Bool ?? true
    }

    // MARK: Cycle de vie

    func start() {
        state = BatteryState.current()
        _ = detector.process(from: nil, to: state)
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        let monitor = PowerSourceMonitor { [weak self] in self?.refresh() }
        monitor.start()
        self.monitor = monitor

        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    func stop() {
        monitor?.stop()
        monitor = nil
        if let lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
        }
        lowPowerObserver = nil
    }

    private func refresh() {
        let old = state
        let new = BatteryState.current()
        if new != old { state = new }
        if let event = detector.process(from: old, to: new) {
            present(event)
        }
    }

    // MARK: Alertes

    private func present(_ event: BatteryEvent) {
        guard let state else { return }
        switch event {
        case .pluggedIn, .unplugged:
            guard alertOnPowerChange else { return }
        case .low:
            guard lowBatteryAlert else { return }
        }
        context.presentAlert(BatteryAlertFactory.alert(for: event, state: state))
    }

    #if DEBUG
    /// Déclenche une alerte sans toucher au chargeur (menu Débogage).
    func simulate(_ event: BatteryEvent) {
        var fake = state ?? BatteryState(level: 64, isCharging: false, isCharged: false, powerSource: .battery)
        switch event {
        case .pluggedIn:
            fake.powerSource = .ac
            fake.isCharging = fake.level < 100
        case .unplugged:
            fake.powerSource = .battery
            fake.isCharging = false
        case let .low(threshold):
            fake.powerSource = .battery
            fake.isCharging = false
            fake.level = threshold
        }
        context.presentAlert(BatteryAlertFactory.alert(for: event, state: fake))
    }
    #endif

    // MARK: Affichage

    var compactPriority: ModulePriority {
        guard let state else { return .none }
        if lowBatteryAlert && !state.isPluggedIn && state.level <= 10 { return .normal }
        return showInCompact ? .low : .none
    }

    func compactLeading() -> AnyView? {
        guard let state else { return nil }
        return AnyView(BatteryGlyph(state: state, isLowPowerMode: isLowPowerMode))
    }

    func compactTrailing() -> AnyView? {
        guard let state else { return nil }
        return AnyView(
            Text("\(state.level) %")
                .monospacedDigit()
                .foregroundStyle(BatteryStyle.textColor(for: state, isLowPowerMode: isLowPowerMode))
        )
    }

    func expandedView() -> AnyView {
        AnyView(BatteryExpandedView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(BatterySettingsView(module: self))
    }
}
