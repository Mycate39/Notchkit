import CoreAudio
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

/// Barre de niveau de l'indicateur (seule alerte plus large que la musique, pour rester lisible).
struct HUDLevelBar: View {
    let state: HUDState

    var body: some View {
        StandByBar(value: CGFloat(state.isMuted ? 0 : state.level), height: 8)
    }
}

// MARK: - Carte : curseurs de volume et de luminosité

struct SystemHUDExpandedView: View {
    let module: SystemHUDModule

    /// Onglets du centre du son.
    enum Tab: CaseIterable { case levels, output, input, apps }
    @State private var tab: Tab = .levels
    @State private var volume: Float = SystemVolume.volume
    @State private var brightness: Float = DisplayBrightness.brightness ?? 0
    @State private var isMuted = SystemVolume.isMuted

    private var audio: AudioCenter { module.audio }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            tabs
            Group {
                switch tab {
                case .levels: levels
                case .output: AudioDeviceList(audio: audio, devices: audio.outputs, selected: audio.defaultOutput, input: false)
                case .input: AudioDeviceList(audio: audio, devices: audio.inputs, selected: audio.defaultInput, input: true)
                case .apps: AudioAppList(audio: audio)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(.opacity)
        }
        .padding(10)
        .animation(NotchLayout.selectionSpring, value: tab)
        .onAppear {
            volume = SystemVolume.volume
            brightness = DisplayBrightness.brightness ?? 0
            isMuted = SystemVolume.isMuted
            audio.start()
        }
        .onDisappear { audio.stop() }
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            tabButton(.levels, symbol: "slider.horizontal.3", help: "Volume et luminosité")
            tabButton(.output, symbol: "hifispeaker.2.fill", help: "Sortie audio")
            tabButton(.input, symbol: "mic.fill", help: "Micro")
            tabButton(.apps, symbol: "square.grid.2x2.fill", help: "Apps qui jouent du son")
        }
        .padding(2)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    private func tabButton(_ value: Tab, symbol: String, help: LocalizedStringKey) -> some View {
        Button { tab = value } label: {
            // Onglet sur toute sa part de largeur : facile à viser.
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: NotchLayout.audioTabHeight)
                .background(tab == value ? StandBy.surface : .clear, in: Capsule())
                .foregroundStyle(.white.opacity(tab == value ? 1 : 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.notch)
        .help(Text(help))
        .accessibilityLabel(Text(help))
    }

    /// Encoche basse : rangées resserrées et boutons plus petits pour que la luminosité reste visible.
    private var levels: some View {
        ViewThatFits(in: .vertical) {
            levels(spacing: 10, button: .regular)
            levels(spacing: 4, button: .small)
        }
    }

    private func levels(spacing: CGFloat, button: StandByButtonStyle.Size) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            row(symbol: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", value: $volume, enabled: SystemVolume.isAdjustable,
                button: button) {
                SystemVolume.volume = $0
            } onSymbolTap: {
                SystemVolume.isMuted.toggle()
                isMuted = SystemVolume.isMuted
            }
            if DisplayBrightness.isAvailable {
                row(symbol: "sun.max.fill", value: $brightness, enabled: true, button: button) {
                    DisplayBrightness.brightness = $0
                } onSymbolTap: {}
            }
            if !SystemVolume.isAdjustable {
                Text("Cette sortie audio n'a pas de volume réglable.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func row(symbol: String, value: Binding<Float>, enabled: Bool, button: StandByButtonStyle.Size,
                     onChange: @escaping (Float) -> Void, onSymbolTap: @escaping () -> Void) -> some View {
        // Style StandBy : symbole dans un cercle sombre, curseur en pilule épaisse ambre.
        HStack(spacing: 8) {
            Button(action: onSymbolTap) {
                Image(systemName: symbol)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.standBy(button, circle: true))
            StandBySlider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Float($0) })) {
                onChange(Float($0))
            }
            .disabled(!enabled)
        }
    }
}

/// Liste des sorties (ou des micros) : un clic choisit l'appareil, son volume s'affiche dessous.
struct AudioDeviceList: View {
    let audio: AudioCenter
    let devices: [AudioDevice]
    let selected: AudioObjectID?
    let input: Bool
    @State private var level: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(devices) { device in
                        Button { audio.makeDefault(device, input: input); readLevel() } label: {
                            HStack(spacing: 7) {
                                Image(systemName: device.symbol)
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 18)
                                Text(device.name).font(.system(size: 12, weight: device.id == selected ? .semibold : .regular)).lineLimit(1)
                                Spacer(minLength: 4)
                                if device.id == selected {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.tint)
                                }
                            }
                            .padding(.horizontal, 8)
                            .frame(minHeight: NotchLayout.audioRowHeight)
                            .background(device.id == selected ? StandBy.surface : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.notch)
                    }
                }
            }
            .scrollIndicators(.never)
            if let selected, audio.volume(of: selected, input: input) != nil {
                HStack(spacing: 8) {
                    Image(systemName: input ? "mic.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    StandBySlider(value: $level, height: 16) { audio.setVolume(Float($0), of: selected, input: input) }
                }
            }
        }
        .onAppear(perform: readLevel)
        .onChange(of: selected) { readLevel() }
    }

    private func readLevel() {
        guard let selected else { return }
        level = Double(audio.volume(of: selected, input: input) ?? 0)
    }
}

/// Apps qui jouent du son en ce moment.
struct AudioAppList: View {
    let audio: AudioCenter

    var body: some View {
        if audio.playingApps.isEmpty {
            Text(availabilityText)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(audio.playingApps) { app in
                        AudioAppRow(audio: audio, app: app)
                    }
                    if let error = audio.appVolumeError {
                        Text(error).font(.system(size: 10)).foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private var availabilityText: LocalizedStringKey {
        if #available(macOS 14.2, *) { return "Aucune app ne joue de son en ce moment." }
        return "La liste des apps qui jouent du son demande macOS 14.2 ou plus récent."
    }
}

// MARK: - Réglages

struct SystemHUDSettingsView: View {
    @Bindable var module: SystemHUDModule

    var body: some View {
        Group {
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
                        Button("Demander l'accès…", action: module.requestAccessibility)
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

/// Une app qui joue : icône, nom et curseur de volume (100 % = son normal, sans interception).
private struct AudioAppRow: View {
    let audio: AudioCenter
    let app: AudioApp
    @State private var volume: Double = 1

    var body: some View {
        HStack(spacing: 7) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            }
            Text(app.name)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .frame(width: 74, alignment: .leading)
            StandBySlider(value: $volume, height: 14) { audio.setVolume(Float($0), for: app) }
                .help(Text("Volume de \(app.name)"))
        }
        .onAppear { volume = Double(audio.appVolumes[app.id] ?? 1) }
    }
}
