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

struct AirPodsExpandedView: View {
    let module: AirPodsModule
    @Environment(\.widgetSize) private var size

    var body: some View {
        Group {
            if let device = module.devices.first(where: \.isDefaultOutput) ?? module.devices.first {
                VStack(spacing: 6) {
                    Image(systemName: device.kind.symbol)
                        .font(.system(size: size == .small ? 26 : 32))
                        .symbolRenderingMode(.hierarchical)
                        .frame(height: 36)
                    Text(device.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let battery = module.battery {
                        BatteryLevelsView(battery: battery)
                    } else if device.isDefaultOutput {
                        Label("Sortie audio active", systemImage: "speaker.wave.2.fill")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    if !device.isDefaultOutput {
                        Button("Utiliser comme sortie") { module.makeDefaultOutput(device) }
                            .controlSize(.mini)
                    }
                    if let unknown = module.unknownModeValue {
                        Text("Mode actuel : \(unknown == 4 ? String(localized: "Adaptatif") : String(localized: "inconnu (\(unknown))"))")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    if !module.supportedModes.isEmpty {
                        // Mode d'écoute (API privée).
                        HStack(spacing: 4) {
                            ForEach(module.supportedModes) { mode in
                                Button { module.setListeningMode(mode) } label: {
                                    Image(systemName: mode.symbol)
                                        .font(.system(size: 11, weight: .semibold))
                                        .frame(width: 30, height: 22)
                                        .background(module.listeningMode == mode ? Color.white.opacity(0.9) : Color.white.opacity(0.12),
                                                    in: Capsule())
                                        .foregroundStyle(module.listeningMode == mode ? .black : .white)
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .help(Text(mode.title))
                            }
                        }
                    } else if size != .small {
                        Button {
                            module.openBluetoothSettings()
                        } label: {
                            Label("Réglages Bluetooth…", systemImage: "gearshape")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.6))
                    }
                    // Plusieurs casques connectés : bascule rapide.
                    if module.devices.count > 1 {
                        HStack(spacing: 6) {
                            ForEach(module.devices.filter { $0.id != device.id }) { other in
                                Button { module.makeDefaultOutput(other) } label: {
                                    Image(systemName: other.kind.symbol)
                                }
                                .buttonStyle(.plain)
                                .help("Passer sur \(other.name)")
                            }
                        }
                        .font(.system(size: 12))
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "headphones")
                        .font(.system(size: 22))
                    Text("Aucun casque Bluetooth connecté")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
        .onAppear { module.refreshBluetoothInfo() }
    }
}

/// Batterie de chaque écouteur et du boîtier (« G 80 % · D 82 % · Boîtier 60 % »).
private struct BatteryLevelsView: View {
    let battery: AirPodsPrivate.Battery

    var body: some View {
        HStack(spacing: 8) {
            if let single = battery.single { level("", single) }
            if let left = battery.left { level("G", left) }
            if let right = battery.right { level("D", right) }
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
            Toggle("Batterie et mode d'écoute des AirPods", isOn: $module.advancedControls)
            HStack {
                Button("Copier le diagnostic") { module.copyDiagnostic() }
                Text("À coller pour signaler un souci (AirPods connectés).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("La batterie de chaque écouteur et le choix du mode (désactivé, réduction du bruit, transparence) utilisent une interface non officielle d'Apple et demandent l'autorisation Bluetooth. Si une mise à jour de macOS la modifie, ces commandes disparaissent simplement de la carte.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
