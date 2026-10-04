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
                    if device.isDefaultOutput {
                        Label("Sortie audio active", systemImage: "speaker.wave.2.fill")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.green)
                    } else {
                        Button("Utiliser comme sortie") { module.makeDefaultOutput(device) }
                            .controlSize(.mini)
                    }
                    if size != .small {
                        Button {
                            module.openBluetoothSettings()
                        } label: {
                            Label("Réduction du bruit…", systemImage: "ear.and.waveform")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.6))
                        .help("Le mode de réduction du bruit se règle dans les réglages Bluetooth de macOS")
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
    }
}

struct AirPodsSettingsView: View {
    @Bindable var module: AirPodsModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Animation à la connexion", isOn: $module.alertOnConnect)
            Toggle("Animation à la déconnexion", isOn: $module.alertOnDisconnect)
            Text("La connexion est détectée quand l'appareil apparaît comme sortie audio. Le mode de réduction du bruit ne peut pas être modifié par une app tierce avec les outils publics d'Apple : le bouton « Réduction du bruit… » ouvre les réglages Bluetooth de macOS.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
