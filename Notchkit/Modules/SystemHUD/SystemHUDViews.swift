import SwiftUI

/// Icône de l'indicateur (haut-parleur ou soleil selon le niveau).
struct HUDIcon: View {
    let state: HUDState

    var body: some View {
        Image(systemName: state.symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 22, alignment: .leading)
    }
}

/// Barre de niveau de l'indicateur.
struct HUDLevelBar: View {
    let state: HUDState

    var body: some View {
        let level = CGFloat(state.isMuted ? 0 : state.level)
        HStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white)
                        .frame(width: max(level > 0 ? 6 : 0, proxy.size.width * level))
                }
            }
            .frame(height: 6)
            Text("\(Int((level * 100).rounded()))")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 22, alignment: .trailing)
        }
    }
}

// MARK: - Carte : curseurs de volume et de luminosité

struct SystemHUDExpandedView: View {
    let module: SystemHUDModule

    @State private var volume: Float = SystemVolume.volume
    @State private var brightness: Float = DisplayBrightness.brightness ?? 0
    @State private var isMuted = SystemVolume.isMuted

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(symbol: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", value: $volume, enabled: SystemVolume.isAdjustable) {
                SystemVolume.volume = $0
            } onSymbolTap: {
                SystemVolume.isMuted.toggle()
                isMuted = SystemVolume.isMuted
            }
            if DisplayBrightness.isAvailable {
                row(symbol: "sun.max.fill", value: $brightness, enabled: true) {
                    DisplayBrightness.brightness = $0
                } onSymbolTap: {}
            }
            if !SystemVolume.isAdjustable {
                Text("Cette sortie audio n'a pas de volume réglable.")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity)
        .onAppear {
            volume = SystemVolume.volume
            brightness = DisplayBrightness.brightness ?? 0
            isMuted = SystemVolume.isMuted
        }
    }

    private func row(symbol: String, value: Binding<Float>, enabled: Bool,
                     onChange: @escaping (Float) -> Void, onSymbolTap: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Button(action: onSymbolTap) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; onChange($0) }), in: 0...1)
                .controlSize(.small)
                .tint(.white)
                .disabled(!enabled)
        }
    }
}

// MARK: - Réglages

struct SystemHUDSettingsView: View {
    @Bindable var module: SystemHUDModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Remplacer l'indicateur de volume et de luminosité de macOS", isOn: $module.replaceSystemHUD)

            if module.replaceSystemHUD {
                if module.isIntercepting {
                    Label("Touches de volume et de luminosité interceptées", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    HStack {
                        Label("Autorisation Accessibilité nécessaire", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Autoriser…", action: module.requestAccessibility)
                    }
                }
            }

            Text("Le volume est réglé par une interface publique. La luminosité de l'écran intégré passe par une interface non officielle d'Apple (DisplayServices) : si une mise à jour de macOS la modifie, les touches de luminosité retrouvent simplement leur comportement normal. Les écrans externes et les sorties sans volume réglable gardent l'indicateur de macOS.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Version de développement : après chaque recompilation, macOS peut demander à nouveau l'autorisation Accessibilité.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
