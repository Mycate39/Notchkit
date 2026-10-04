import Foundation

/// Niveaux de batterie d'un appareil Bluetooth (en %), tels que macOS les connaît.
struct BluetoothBattery: Equatable, Sendable {
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    /// Batterie unique (souris, clavier, casque sans écouteurs séparés).
    var main: Int?

    var isEmpty: Bool { left == nil && right == nil && caseLevel == nil && main == nil }

    /// Niveau à afficher en un seul chiffre : le plus bas des écouteurs, sinon la batterie unique.
    var summary: Int? {
        [left, right].compactMap { $0 }.min() ?? main
    }
}

/// Appareil Bluetooth connecté, avec sa batterie.
struct BluetoothDeviceInfo: Identifiable, Equatable, Sendable {
    let name: String
    /// Adresse normalisée (chiffres hexadécimaux en minuscules, sans séparateurs).
    let address: String
    /// Catégorie donnée par macOS (« Headphones », « Mouse », « Keyboard »…).
    let minorType: String?
    var battery: BluetoothBattery

    var id: String { address.isEmpty ? name : address }

    /// Pictogramme selon la catégorie.
    var symbol: String {
        switch minorType?.lowercased() {
        case "mouse": "computermouse"
        case "keyboard": "keyboard"
        case "trackpad": "rectangle.and.hand.point.up.left"
        case "headphones", "headset": HeadphoneDevice.Kind(name: name).symbol
        case "gamepad", "joystick": "gamecontroller"
        default: "dot.radiowaves.left.and.right"
        }
    }

    /// Normalise une adresse (« 30:0E:43… », « 30-0e-43…:output ») pour comparer.
    static func normalized(_ address: String) -> String {
        String(address.lowercased().filter(\.isHexDigit))
    }
}

/// Lecture des appareils Bluetooth connectés et de leur batterie via `system_profiler`
/// (outil fourni par macOS, aucune API privée).
enum BluetoothInventory {
    /// Lance `system_profiler` hors du thread principal (≈ 1 s) et renvoie les appareils connectés.
    static func load() async -> [BluetoothDeviceInfo] {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return []
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return parse(data)
        }.value
    }

    /// Extrait les appareils connectés de la sortie JSON de `system_profiler SPBluetoothDataType -json`.
    static func parse(_ data: Data) -> [BluetoothDeviceInfo] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }
        var devices: [BluetoothDeviceInfo] = []
        for controller in controllers {
            // Chaque entrée est un dictionnaire { "Nom de l'appareil": { propriétés } }.
            guard let connected = controller["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    devices.append(BluetoothDeviceInfo(
                        name: name,
                        address: BluetoothDeviceInfo.normalized(info["device_address"] as? String ?? ""),
                        minorType: info["device_minorType"] as? String,
                        battery: battery(from: info)
                    ))
                }
            }
        }
        return devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Lit les champs « device_batteryLevel… » (valeurs du type « 85% »).
    static func battery(from info: [String: Any]) -> BluetoothBattery {
        func level(_ key: String) -> Int? {
            guard let text = info[key] as? String else { return nil }
            return Int(text.filter(\.isNumber)).map { min(100, $0) }
        }
        var battery = BluetoothBattery(
            left: level("device_batteryLevelLeft"),
            right: level("device_batteryLevelRight"),
            caseLevel: level("device_batteryLevelCase"),
            main: level("device_batteryLevelMain") ?? level("device_batteryLevel")
        )
        // Autre champ de batterie inconnu : on le prend comme batterie unique.
        if battery.isEmpty,
           let key = info.keys.sorted().first(where: { $0.hasPrefix("device_batteryLevel") }) {
            battery.main = level(key)
        }
        return battery
    }
}
