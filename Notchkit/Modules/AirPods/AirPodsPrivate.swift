import CoreBluetooth
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

    /// Identifiants produit connus de casques Apple avec réduction de bruit (AirPods Pro, Pro 2,
    /// Max, AirPods 4 avec réduction de bruit…). Liste indicative : macOS ne signale pas toujours
    /// correctement l'ANC des modèles récents.
    static let knownNoiseCancellingProductIDs: Set<UInt16> = [0x200E, 0x2014, 0x2024, 0x200A, 0x201F, 0x201B, 0x2027]

    static func supportedModes(of device: IOBluetoothDevice) -> [ListeningMode] {
        guard device.responds(to: NSSelectorFromString("setListeningMode:")) else { return [] }
        let name = (device.name ?? "").lowercased()
        let productID = uint16(device, "productID") ?? 0
        // Plusieurs indices, car l'indicateur officieux est parfois faux pour les modèles récents.
        let hasANC = bool(device, "isANCSupported")
            || uint32(device, "listeningModeConfigs").map { $0 != 0 } == true
            || knownNoiseCancellingProductIDs.contains(productID)
            || name.contains("pro") || name.contains("max")
        guard hasANC else { return [] }
        return [.off, .noiseCancellation, .transparency]
    }

    /// Valeur brute du mode actuel (pour afficher un mode inconnu, ex. « Adaptatif »).
    static func rawListeningMode(of device: IOBluetoothDevice) -> UInt8? {
        uint8(device, "listeningMode")
    }

    /// Texte de diagnostic (à copier pour signaler un problème).
    static func diagnostic(for headphones: [HeadphoneDevice]) -> String {
        var lines: [String] = []
        let authorization: String = switch CBManager.authorization {
        case .allowedAlways: "autorisée"
        case .denied: "REFUSÉE"
        case .restricted: "restreinte"
        case .notDetermined: "pas encore demandée"
        @unknown default: "inconnue"
        }
        lines.append("Autorisation Bluetooth : \(authorization)")
        lines.append("Sorties audio Bluetooth : " + (headphones.isEmpty ? "aucune" : headphones.map { "\($0.name) [\($0.uid)]" }.joined(separator: ", ")))
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        lines.append("Appareils appairés lisibles : \(paired.count)")
        for headphone in headphones {
            guard let device = bluetoothDevice(for: headphone) else {
                lines.append("• \(headphone.name) : appareil Bluetooth NON trouvé")
                continue
            }
            let selectors = ["listeningMode", "setListeningMode:", "isANCSupported", "isTransparencySupported", "listeningModeConfigs", "productID"]
                .map { "\($0)=\(device.responds(to: NSSelectorFromString($0)) ? "oui" : "non")" }
            lines.append("• \(device.name ?? "?") (\(device.addressString ?? "?"), connecté : \(device.isConnected()))")
            lines.append("  méthodes : " + selectors.joined(separator: " "))
            lines.append("  produit : 0x\(String(uint16(device, "productID") ?? 0, radix: 16, uppercase: true)), mode actuel : \(uint8(device, "listeningMode").map(String.init) ?? "?"), configs : \(uint32(device, "listeningModeConfigs").map { String($0, radix: 2) } ?? "?")")
            lines.append("  ANC signalé : \(bool(device, "isANCSupported")), transparence signalée : \(bool(device, "isTransparencySupported"))")
            let battery = battery(of: device)
            lines.append("  batterie : G \(battery.left.map(String.init) ?? "-") D \(battery.right.map(String.init) ?? "-") boîtier \(battery.caseLevel.map(String.init) ?? "-") unique \(battery.single.map(String.init) ?? "-")")
        }
        return lines.joined(separator: "\n")
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

    private static func uint16(_ object: NSObject, _ name: String) -> UInt16? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> UInt16
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }

    private static func uint32(_ object: NSObject, _ name: String) -> UInt32? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> UInt32
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }

    private static func bool(_ object: NSObject, _ name: String) -> Bool {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return false }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
    }
}
