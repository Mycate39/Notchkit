import AppKit
import SwiftUI
import Observation

/// Module AirPods et casques : animation à la connexion et carte de l'appareil connecté.
///
/// La connexion est détectée via la liste des sorties audio (Core Audio, API publique).
/// Le mode de réduction de bruit (ANC) n'est pas modifiable par une API publique :
/// la carte ouvre les réglages Bluetooth de macOS, où il se règle.
@MainActor
@Observable
final class AirPodsModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "airpods",
        name: "AirPods et casques",
        summary: "Animation à la connexion de vos AirPods ou d'un casque Bluetooth, sortie audio en un clic.",
        systemImage: "airpods.pro",
        category: .system,
        tier: .free,
        defaultEnabled: true
    )

    private(set) var devices: [HeadphoneDevice] = []
    /// Batterie et mode d'écoute de l'appareil principal (API privée, voir `AirPodsPrivate`).
    private(set) var battery: AirPodsPrivate.Battery?
    private(set) var listeningMode: AirPodsPrivate.ListeningMode?
    private(set) var supportedModes: [AirPodsPrivate.ListeningMode] = []

    /// Lire la batterie et piloter le mode d'écoute (demande l'autorisation Bluetooth).
    var advancedControls: Bool {
        didSet {
            UserDefaults.standard.set(advancedControls, forKey: Keys.advancedControls)
            refreshBluetoothInfo()
        }
    }

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
        static let advancedControls = "module.airpods.advancedControls"
    }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private let monitor = AudioDeviceMonitor()

    init(context: ModuleContext) {
        self.context = context
        let defaults = UserDefaults.standard
        alertOnConnect = defaults.object(forKey: Keys.alertOnConnect) as? Bool ?? true
        alertOnDisconnect = defaults.object(forKey: Keys.alertOnDisconnect) as? Bool ?? false
        advancedControls = defaults.object(forKey: Keys.advancedControls) as? Bool ?? true
    }

    func start() {
        monitor.onChange = { [weak self] devices in self?.update(devices) }
        monitor.start()
        devices = monitor.devices  // état initial : pas d'animation au lancement de l'app
    }

    func stop() {
        monitor.stop()
        monitor.onChange = nil
        devices = []
    }

    private func update(_ newDevices: [HeadphoneDevice]) {
        for event in HeadphoneEvent.events(from: devices, to: newDevices) {
            switch event {
            case let .connected(device) where alertOnConnect:
                // Batterie lue juste après la connexion (les AirPods la transmettent en quelques secondes).
                devices = newDevices
                refreshBluetoothInfo()
                context.presentAlert(AirPodsAlerts.connected(device, battery: battery))
            case let .disconnected(device) where alertOnDisconnect:
                context.presentAlert(AirPodsAlerts.disconnected(device))
            default:
                break
            }
        }
        devices = newDevices
    }

    // MARK: Actions

    /// Appareil principal : la sortie active, sinon le premier casque connecté.
    var primaryDevice: HeadphoneDevice? {
        devices.first(where: \.isDefaultOutput) ?? devices.first
    }

    /// Relit batterie et mode d'écoute (à l'ouverture de la carte et après la connexion).
    func refreshBluetoothInfo() {
        guard advancedControls, !AutomatedRun.isActive, let primary = primaryDevice,
              let device = AirPodsPrivate.bluetoothDevice(for: primary)
        else {
            battery = nil
            listeningMode = nil
            supportedModes = []
            return
        }
        let newBattery = AirPodsPrivate.battery(of: device)
        battery = newBattery.isEmpty ? nil : newBattery
        supportedModes = AirPodsPrivate.supportedModes(of: device)
        listeningMode = AirPodsPrivate.listeningMode(of: device)
    }

    func setListeningMode(_ mode: AirPodsPrivate.ListeningMode) {
        guard let primary = primaryDevice, let device = AirPodsPrivate.bluetoothDevice(for: primary) else { return }
        AirPodsPrivate.setListeningMode(mode, on: device)
        listeningMode = mode
        context.presentAlert(NotchAlert(
            leading: AnyView(Image(systemName: mode.symbol).foregroundStyle(.white)),
            trailing: AnyView(Text(mode.title).foregroundStyle(.white).minimumScaleFactor(0.6)),
            duration: .seconds(1.8),
            sideWidth: 100
        ))
        // Le changement prend un instant : on relit l'état réel.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.refreshBluetoothInfo()
        }
    }

    func makeDefaultOutput(_ device: HeadphoneDevice) {
        monitor.makeDefaultOutput(device)
    }

    /// Réglages Bluetooth de macOS (mode de réduction de bruit, détection automatique…).
    func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Affichage

    var compactPriority: ModulePriority { .none }

    var expandedWidthWeight: CGFloat { 1.5 }

    func miniView() -> AnyView {
        guard let device = devices.first(where: \.isDefaultOutput) ?? devices.first else {
            return AnyView(MiniWidget(symbol: "headphones", value: nil, caption: String(localized: "Non connecté")))
        }
        return AnyView(MiniWidget(symbol: device.kind.symbol, value: nil, caption: device.name))
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
    static func connected(_ device: HeadphoneDevice, battery: AirPodsPrivate.Battery? = nil) -> NotchAlert {
        NotchAlert(
            leading: AnyView(ConnectedHeadphonesIcon(symbol: device.kind.symbol)),
            trailing: AnyView(
                Group {
                    if let level = battery?.lowestBud {
                        Label("\(level) %", systemImage: "battery.75percent")
                            .labelStyle(.titleAndIcon)
                            .monospacedDigit()
                    } else {
                        Text("Connectés")
                    }
                }
                .foregroundStyle(.green)
                .minimumScaleFactor(0.8)
            ),
            duration: .seconds(3)
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
