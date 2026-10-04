import Foundation
import IOBluetooth

/// Mode d'écoute et batterie des AirPods.
///
/// ⚠️ API PRIVÉE : méthodes non documentées de `IOBluetoothDevice` (`listeningMode`,
/// `setListeningMode:`, `batteryPercentLeft`…), appelées seulement si elles existent.
/// Si une mise à jour de macOS les retire, les commandes disparaissent simplement de la carte.
/// L'accès aux appareils Bluetooth demande l'autorisation « Bluetooth » de macOS.
enum AirPodsPrivate {
    enum ListeningMode: UInt8, CaseIterable, Identifiable, Sendable {
        case off = 1
        case noiseCancellation = 2
        case transparency = 3

        var id: UInt8 { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .off: "Désactivé"
            case .noiseCancellation: "Réduction du bruit"
            case .transparency: "Transparence"
            }
        }

        var symbol: String {
            switch self {
            case .off: "speaker.wave.1"
            case .noiseCancellation: "ear.and.waveform"
            case .transparency: "ear"
            }
        }
    }

    struct Battery: Equatable, Sendable {
        var left: Int?
        var right: Int?
        var caseLevel: Int?
        /// Casque à une seule batterie (AirPods Max, Beats…).
        var single: Int?

        /// Niveau le plus bas des écouteurs (pour l'alerte de connexion).
        var lowestBud: Int? {
            [left, right, single].compactMap { $0 }.min()
        }

        var isEmpty: Bool { left == nil && right == nil && caseLevel == nil && single == nil }
    }

    // MARK: - Appareil Bluetooth correspondant

    /// Appareil Bluetooth connecté correspondant à une sortie audio (adresse dans l'UID, sinon nom).
    static func bluetoothDevice(for headphone: HeadphoneDevice) -> IOBluetoothDevice? {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return nil }
        let connected = paired.filter { $0.isConnected() }
        let uid = normalized(headphone.uid)
        return connected.first { device in
            guard let address = device.addressString else { return false }
            return uid.contains(normalized(address))
        } ?? connected.first { $0.name == headphone.name }
    }

    /// Adresse ou UID réduit à ses caractères hexadécimaux (« AC-90-85… » → « ac9085… »).
    static func normalized(_ string: String) -> String {
        string.lowercased().filter { $0.isHexDigit }
    }

    // MARK: - Mode d'écoute

    static func supportedModes(of device: IOBluetoothDevice) -> [ListeningMode] {
        guard device.responds(to: NSSelectorFromString("setListeningMode:")) else { return [] }
        var modes: [ListeningMode] = [.off]
        if bool(device, "isANCSupported") { modes.append(.noiseCancellation) }
        if bool(device, "isTransparencySupported") { modes.append(.transparency) }
        return modes.count > 1 ? modes : []
    }

    static func listeningMode(of device: IOBluetoothDevice) -> ListeningMode? {
        uint8(device, "listeningMode").flatMap(ListeningMode.init(rawValue:))
    }

    static func setListeningMode(_ mode: ListeningMode, on device: IOBluetoothDevice) {
        let selector = NSSelectorFromString("setListeningMode:")
        guard device.responds(to: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, UInt8) -> Void
        let implementation = unsafeBitCast(device.method(for: selector), to: Setter.self)
        implementation(device, selector, mode.rawValue)
    }

    // MARK: - Batterie

    static func battery(of device: IOBluetoothDevice) -> Battery {
        func level(_ name: String) -> Int? {
            uint8(device, name).flatMap { $0 > 0 && $0 <= 100 ? Int($0) : nil }
        }
        return Battery(
            left: level("batteryPercentLeft"),
            right: level("batteryPercentRight"),
            caseLevel: level("batteryPercentCase"),
            single: level("batteryPercentSingle")
        )
    }

    // MARK: - Appels dynamiques

    private static func uint8(_ object: NSObject, _ name: String) -> UInt8? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> UInt8
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }

    private static func bool(_ object: NSObject, _ name: String) -> Bool {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return false }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }
}
