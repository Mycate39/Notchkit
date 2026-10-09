import AppKit
import SwiftUI
import Observation

/// Module AirPods et casques : animation à la connexion et logo de l'appareil connecté.
///
/// La connexion est détectée via la liste des sorties audio (Core Audio, API publique) ;
/// la batterie des appareils Bluetooth est lue avec `system_profiler` (outil de macOS).
@MainActor
@Observable
final class AirPodsModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "airpods",
        name: "AirPods et casques",
        summary: "Animation à la connexion de vos AirPods ou d'un casque Bluetooth, et appareil connecté en un coup d'œil.",
        systemImage: "airpods.pro",
        category: .system,
        tier: .free,
        defaultEnabled: true
    )

    private(set) var devices: [HeadphoneDevice] = []
    /// Appareils Bluetooth connectés (casques, souris, claviers…) avec leur batterie.
    private(set) var bluetoothDevices: [BluetoothDeviceInfo] = []

    /// Animation dans l'encoche à la connexion.
    var alertOnConnect: Bool {
        didSet { UserDefaults.standard.set(alertOnConnect, forKey: Keys.alertOnConnect) }
    }
    /// Animation à la déconnexion.
    var alertOnDisconnect: Bool {
        didSet { UserDefaults.standard.set(alertOnDisconnect, forKey: Keys.alertOnDisconnect) }
    }

    private enum Keys {
        static let alertOnConnect = "module.airpods.alertOnConnect"
        static let alertOnDisconnect = "module.airpods.alertOnDisconnect"
    }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private let monitor = AudioDeviceMonitor()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var isRefreshing = false

    init(context: ModuleContext) {
        self.context = context
        let defaults = UserDefaults.standard
        alertOnConnect = defaults.object(forKey: Keys.alertOnConnect) as? Bool ?? true
        alertOnDisconnect = defaults.object(forKey: Keys.alertOnDisconnect) as? Bool ?? false
    }

    func start() {
        monitor.onChange = { [weak self] devices in self?.update(devices) }
        monitor.start()
        devices = monitor.devices  // état initial : pas d'animation au lancement de l'app
        refreshBattery()
        // Relecture toutes les 5 minutes (la batterie évolue lentement ; ≈ 1 s de calcul à chaque fois).
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                self?.refreshBattery()
            }
        }
    }

    func stop() {
        monitor.stop()
        monitor.onChange = nil
        refreshTask?.cancel()
        pollingTask?.cancel()
        devices = []
        bluetoothDevices = []
    }

    /// Relit la batterie des appareils Bluetooth (sans effet dans les tests automatisés).
    func refreshBattery() {
        guard !AutomatedRun.isActive, !isRefreshing else { return }
        isRefreshing = true
        Task { [weak self] in
            let devices = await BluetoothInventory.load()
            guard let self else { return }
            self.isRefreshing = false
            if devices != self.bluetoothDevices { self.bluetoothDevices = devices }
        }
    }

    /// Juste après une connexion, la batterie arrive en quelques secondes : plusieurs relectures.
    private func refreshAfterConnection() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            for delay in [0.5, 2.5, 6.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.refreshBattery()
            }
        }
    }

    /// Batterie d'un casque (retrouvé par son adresse Bluetooth, sinon par son nom).
    func battery(for device: HeadphoneDevice) -> BluetoothBattery? {
        let address = BluetoothDeviceInfo.normalized(device.uid)
        let match = bluetoothDevices.first { !$0.address.isEmpty && address.contains($0.address) }
            ?? bluetoothDevices.first { $0.name == device.name }
        guard let battery = match?.battery, !battery.isEmpty else { return nil }
        return battery
    }

    /// Autres appareils Bluetooth connectés ayant une batterie (souris, clavier…).
    var otherBatteryDevices: [BluetoothDeviceInfo] {
        let primaryAddress = primaryDevice.map { BluetoothDeviceInfo.normalized($0.uid) } ?? ""
        return bluetoothDevices.filter { info in
            !info.battery.isEmpty && info.name != primaryDevice?.name
                && (info.address.isEmpty || !primaryAddress.contains(info.address))
        }
    }

    private func update(_ newDevices: [HeadphoneDevice]) {
        let events = HeadphoneEvent.events(from: devices, to: newDevices)
        if !events.isEmpty { refreshAfterConnection() }
        for event in events {
            switch event {
            case let .connected(device) where alertOnConnect:
                context.presentAlert(AirPodsAlerts.connected(device, module: self))
            case let .disconnected(device) where alertOnDisconnect:
                context.presentAlert(AirPodsAlerts.disconnected(device))
            default:
                break
            }
        }
        devices = newDevices
    }

    /// Appareil principal : la sortie active, sinon le premier casque connecté.
    var primaryDevice: HeadphoneDevice? {
        devices.first(where: \.isDefaultOutput) ?? devices.first
    }

    // MARK: Affichage

    var compactPriority: ModulePriority { .none }

    func miniView() -> AnyView {
        guard let device = primaryDevice else {
            return AnyView(MiniWidget(symbol: "headphones", value: nil, caption: String(localized: "Non connecté")))
        }
        return AnyView(MiniWidget(symbol: device.kind.symbol, value: battery(for: device)?.summary.map { "\($0) %" },
                                  caption: device.name))
    }

    func expandedView() -> AnyView {
        AnyView(AirPodsExpandedView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(AirPodsSettingsView(module: self))
    }
}

enum AirPodsAlerts {
    @MainActor
    static func connected(_ device: HeadphoneDevice, module: AirPodsModule) -> NotchAlert {
        NotchAlert(
            leading: AnyView(ConnectedHeadphonesIcon(symbol: device.kind.symbol)),
            trailing: AnyView(ConnectedBatteryLabel(module: module, device: device)),
            duration: .seconds(4)
        )
    }

    @MainActor
    static func disconnected(_ device: HeadphoneDevice) -> NotchAlert {
        NotchAlert(
            leading: AnyView(Image(systemName: device.kind.symbol).foregroundStyle(.white.opacity(0.6))),
            trailing: AnyView(Text("Déconnectés").foregroundStyle(.white.opacity(0.6)).minimumScaleFactor(0.7)),
            duration: .seconds(2)
        )
    }
}

#if DEBUG
extension AirPodsModule {
    /// Casque fictif pour les images de démonstration.
    func debugSetDevices(_ devices: [HeadphoneDevice], bluetooth: [BluetoothDeviceInfo]) {
        self.devices = devices
        bluetoothDevices = bluetooth
    }
}
#endif
