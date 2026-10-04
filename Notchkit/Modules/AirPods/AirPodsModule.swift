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
                context.presentAlert(AirPodsAlerts.connected(device))
            case let .disconnected(device) where alertOnDisconnect:
                context.presentAlert(AirPodsAlerts.disconnected(device))
            default:
                break
            }
        }
        devices = newDevices
    }

    // MARK: Actions

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

    func expandedView() -> AnyView {
        AnyView(AirPodsExpandedView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(AirPodsSettingsView(module: self))
    }
}

enum AirPodsAlerts {
    @MainActor
    static func connected(_ device: HeadphoneDevice) -> NotchAlert {
        NotchAlert(
            leading: AnyView(ConnectedHeadphonesIcon(symbol: device.kind.symbol)),
            trailing: AnyView(
                Text("Connectés")
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
