import SwiftUI

/// Onglet « Apparence » : taille de l'encoche, animations et couleurs, avec un aperçu en direct.
struct AppearanceSettingsView: View {
    @Bindable var settings: SettingsStore

    private var appearance: Binding<NotchAppearance> { $settings.settings.appearance }

    var body: some View {
        Form {
            Section {
                AppearancePreview(appearance: settings.settings.appearance)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            Section("Taille de l'encoche dépliée") {
                Picker("Taille", selection: appearance.size) {
                    ForEach(NotchAppearance.Size.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                if settings.settings.appearance.size == .custom {
                    LabeledContent("Largeur") {
                        HStack {
                            Slider(value: $settings.settings.appearance.customWidth, in: NotchAppearance.customWidthRange, step: 10)
                            Text("\(Int(settings.settings.appearance.customWidth)) pt").monospacedDigit().frame(width: 56, alignment: .trailing)
                        }
                    }
                    LabeledContent("Hauteur") {
                        HStack {
                            Slider(value: $settings.settings.appearance.customHeight, in: NotchAppearance.customHeightRange, step: 2)
                            Text("\(Int(settings.settings.appearance.customHeight)) pt").monospacedDigit().frame(width: 56, alignment: .trailing)
                        }
                    }
                }
                Text("Une encoche plus grande accueille plus de widgets par page (\(settings.settings.appearance.pageCapacity.formatted()) unités de largeur).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Animations") {
                // Liaison explicite : sur un Binding, « .animation » désigne une méthode de SwiftUI.
                Picker("Style", selection: Binding(
                    get: { settings.settings.appearance.animation },
                    set: { settings.settings.appearance.animation = $0 }
                )) {
                    ForEach(NotchAppearance.AnimationStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    Label("« Réduire les animations » est activé dans macOS : les animations sont désactivées.", systemImage: "figure.walk")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Couleurs") {
                Picker("Fond de l'encoche", selection: appearance.background) {
                    ForEach(NotchAppearance.Background.allCases) { background in
                        Text(background.title).tag(background)
                    }
                }
                if settings.settings.appearance.background == .custom {
                    ColorPicker("Couleur du fond", selection: Binding(
                        get: { settings.settings.appearance.customBackground.color },
                        set: { settings.settings.appearance.customBackground = StoredColor($0) }
                    ), supportsOpacity: false)
                }
                if settings.settings.appearance.background != .black {
                    Text("En mode encoche (réelle ou simulée), le fond reste toujours noir pour se fondre avec la découpe de l'écran : ce choix s'applique à la pastille flottante. « Verre » utilise le Liquid Glass de macOS 26.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Couleur personnalisée (onglets, barres de progression)", isOn: Binding(
                    get: { settings.settings.appearance.accent != nil },
                    set: { settings.settings.appearance.accent = $0 ? StoredColor(.orange) : nil }
                ))
                if settings.settings.appearance.accent != nil {
                    ColorPicker("Couleur d'accent", selection: Binding(
                        get: { settings.settings.appearance.accentColor },
                        set: { settings.settings.appearance.accent = StoredColor($0) }
                    ), supportsOpacity: false)
                }
            }

            Section {
                Button("Rétablir l'apparence par défaut") {
                    settings.settings.appearance = NotchAppearance()
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Aperçu de l'encoche dépliée avec l'apparence choisie (rejoue l'animation à chaque changement).
private struct AppearancePreview: View {
    let appearance: NotchAppearance
    @State private var expanded = true

    var body: some View {
        let size = appearance.expandedSize
        let scale: CGFloat = 0.62
        let style = appearance.animation.spring

        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Capsule().fill(appearance.accentColor).frame(width: 46, height: 16)
                Capsule().fill(.white.opacity(0.15)).frame(width: 34, height: 16)
                Spacer()
                Image(systemName: "gearshape.fill").foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 10) {
                ForEach(0..<3) { index in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .overlay(alignment: .bottomLeading) {
                            Capsule().fill(index == 0 ? appearance.accentColor : .white.opacity(0.3))
                                .frame(width: 40, height: 5)
                                .padding(10)
                        }
                }
            }
        }
        .padding(16)
        .frame(width: size.width * scale, height: (expanded ? size.height : 40) * scale)
        .background(NotchBackground(appearance: appearance))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18, style: .continuous))
        .environment(\.colorScheme, .dark)
        .frame(height: size.height * scale, alignment: .top)
        .onChange(of: appearance) {
            // Petite démonstration de l'animation choisie.
            expanded = false
            withAnimation(.spring(duration: max(0.15, style.duration), bounce: style.bounce)) { expanded = true }
        }
    }
}
