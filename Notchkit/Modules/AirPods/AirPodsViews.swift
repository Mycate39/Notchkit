import SwiftUI

/// Icône animée de l'alerte de connexion : l'appareil apparaît avec un rebond,
/// entouré d'un anneau vert qui se dessine (animation jouée une seule fois).
struct ConnectedHeadphonesIcon: View {
    let symbol: String
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: appeared ? 1 : 0)
                .stroke(.green, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 20, height: 20)
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .scaleEffect(appeared ? 1 : 0.3)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.5).delay(0.1)) { appeared = true }
        }
    }
}

/// Texte de l'alerte de connexion : « Connectés », remplacé par la batterie dès qu'elle est connue.
struct ConnectedBatteryLabel: View {
    let module: AirPodsModule
    let device: HeadphoneDevice

    var body: some View {
        Group {
            if let level = module.battery(for: device)?.summary {
                Label("\(level) %", systemImage: BatterySymbol.name(for: level))
                    .labelStyle(.titleAndIcon)
                    .monospacedDigit()
                    .foregroundStyle(level <= 20 ? .red : .green)
            } else {
                Text("Connectés").foregroundStyle(.green)
            }
        }
        .minimumScaleFactor(0.8)
        .animation(.easeInOut(duration: 0.25), value: module.battery(for: device))
    }
}

enum BatterySymbol {
    static func name(for level: Int) -> String {
        switch level {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

/// Carte : le logo de l'appareil connecté, son nom et sa batterie, sans aucune commande.
struct AirPodsExpandedView: View {
    let module: AirPodsModule
    @Environment(\.widgetSize) private var size

    var body: some View {
        VStack(spacing: 8) {
            if let device = module.primaryDevice {
                Image(systemName: device.kind.symbol)
                    .font(.system(size: size == .small ? 34 : 42))
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
                Text(device.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let battery = module.battery(for: device) {
                    BatteryLevelsView(battery: battery)
                }
            } else if module.otherBatteryDevices.isEmpty {
                Image(systemName: "headphones")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.4))
                Text("Aucun casque connecté")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            // Autres appareils Bluetooth avec batterie (souris, clavier…).
            if !module.otherBatteryDevices.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(module.otherBatteryDevices.prefix(size == .small ? 2 : 4))) { other in
                        if let level = other.battery.summary {
                            HStack(spacing: 3) {
                                Image(systemName: other.symbol)
                                Text("\(level) %").foregroundStyle(level <= 20 ? .red : .white)
                            }
                            .help(other.name)
                        }
                    }
                }
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
        .onAppear { module.refreshBattery() }
    }
}

/// Batterie de chaque écouteur et du boîtier (« G 80 % · D 82 % · Boîtier 60 % »).
private struct BatteryLevelsView: View {
    let battery: BluetoothBattery

    var body: some View {
        HStack(spacing: 8) {
            if let main = battery.main, battery.left == nil, battery.right == nil { level("", main) }
            if let left = battery.left { level(String(localized: "G", comment: "Écouteur gauche (Left)"), left) }
            if let right = battery.right { level(String(localized: "D", comment: "Écouteur droit (Right)"), right) }
            if let caseLevel = battery.caseLevel { level(String(localized: "Boîtier"), caseLevel) }
        }
        .font(.system(size: 9, weight: .semibold).monospacedDigit())
    }

    private func level(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 2) {
            if !label.isEmpty { Text(label).foregroundStyle(.white.opacity(0.5)) }
            Text("\(value) %").foregroundStyle(value <= 20 ? .red : .white)
        }
    }
}

struct AirPodsSettingsView: View {
    @Bindable var module: AirPodsModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Animation à la connexion", isOn: $module.alertOnConnect)
            Toggle("Animation à la déconnexion", isOn: $module.alertOnDisconnect)
        }
    }
}
