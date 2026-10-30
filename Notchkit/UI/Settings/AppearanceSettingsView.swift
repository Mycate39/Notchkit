import SwiftUI

/// Onglet « Apparence » : animations, mascotte et couleurs, avec un aperçu en direct.
struct AppearanceSettingsView: View {
    @Bindable var settings: SettingsStore

    private var appearance: Binding<NotchAppearance> { $settings.settings.appearance }

    /// Mode encoche (encoche simulée, ou écran avec encoche) : le fond y reste toujours noir.
    private var isNotchMode: Bool {
        settings.settings.simulateNotch || NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    }

    var body: some View {
        Form {
            Section {
                AppearancePreview(appearance: settings.settings.appearance, style: isNotchMode ? .notch : .pill)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
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

            Section("Mascotte") {
                MascotPicker(selection: $settings.settings.mascot)
                Toggle(isOn: $settings.settings.mascotSounds) {
                    Text("Sons de la mascotte")
                    Text("Au clic et quand un agent change d'humeur (au travail, en attente de votre réponse, tâche terminée).")
                }
                if settings.settings.mascotSounds {
                    LabeledContent("Volume") {
                        HStack {
                            Slider(value: $settings.settings.mascotSoundVolume, in: 0.05...1)
                                .frame(maxWidth: 220)
                            Button("Écouter") { MascotSounds.shared.play(.happy) }
                        }
                    }
                }
            }

            Section("Couleurs") {
                Picker("Fond de l'encoche", selection: appearance.background) {
                    ForEach(NotchAppearance.Background.allCases) { background in
                        Text(background.title).tag(background)
                    }
                }
                if isNotchMode {
                    Label("En mode encoche, le haut reste noir pour se fondre avec la découpe de l'écran ; avec « Verre », l'encoche ouverte passe au verre sous la découpe.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if settings.settings.appearance.background == .glass {
                    Text("« Verre » utilise le Liquid Glass de macOS 26 ; en mode encoche (réelle ou simulée), le haut reste noir pour se fondre avec la découpe de l'écran.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Couleur personnalisée (boutons, barres de progression)", isOn: Binding(
                    get: { settings.settings.appearance.accent != nil },
                    set: { settings.settings.appearance.accent = $0 ? StandBy.defaultAccent : nil }
                ))
                Text("Par défaut : bleu, comme les commandes de macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.settings.appearance.accent != nil {
                    ColorPicker("Couleur d'accent", selection: Binding(
                        get: { settings.settings.appearance.accentColor },
                        set: { settings.settings.appearance.accent = StoredColor($0) }
                    ), supportsOpacity: false)
                }
                Toggle(isOn: Binding(
                    get: { settings.settings.appearance.sliderColor != nil },
                    set: { settings.settings.appearance.sliderColor = $0 ? StoredColor(.blue) : nil }
                )) {
                    Text("Couleur propre aux curseurs")
                    Text("Volume, luminosité, volume des apps… Sinon, ils prennent la couleur d'accent.")
                }
                if let color = settings.settings.appearance.sliderColor {
                    ColorPicker("Couleur des curseurs", selection: Binding(
                        get: { color.color },
                        set: { settings.settings.appearance.sliderColor = StoredColor($0) }
                    ), supportsOpacity: false)
                }
            }

            Section {
                Button("Rétablir l'apparence par défaut") {
                    settings.settings.appearance = NotchAppearance()
                }
                .disabled(settings.settings.appearance == NotchAppearance())
            }
        }
        .formStyle(.grouped)
    }
}

/// Aperçu de l'encoche dépliée avec l'apparence choisie, sur un fond d'écran coloré pour que le verre
/// se voie : même forme (oreilles et grands coins) et même fond que l'encoche réelle ; rejoue
/// l'animation choisie à chaque changement.
private struct AppearancePreview: View {
    let appearance: NotchAppearance
    let style: NotchStyle
    @State private var expanded = true

    private static let scale: CGFloat = 0.62

    var body: some View {
        let scale = Self.scale
        let size = NotchLayout.defaultExpandedSize
        let spring = appearance.animation.spring
        let radii = NotchLayout.cornerRadii(for: style, isExpanded: true, height: size.height)
        let ear = style == .notch ? NotchLayout.glassEarRadius * scale : 0
        let shape = NotchShape(earRadius: ear, topCornerRadius: radii.top * scale, bottomCornerRadius: radii.bottom * scale)

        VStack(spacing: 8) {
            HStack {
                Spacer()
                Image(systemName: "gearshape.fill").foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 10) {
                ForEach(0..<3) { index in
                    // Fond « Verre » : widgets posés sur le verre, sans carte.
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(appearance.usesGlassWidgets ? Color.clear : .white.opacity(0.08))
                        .overlay(alignment: .bottomLeading) {
                            Capsule().fill(index == 0 ? appearance.accentColor : .white.opacity(0.3))
                                .frame(width: 40, height: 5)
                                .padding(10)
                        }
                }
            }
            .opacity(expanded ? 1 : 0)
        }
        .padding(.horizontal, ear + 16)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .frame(width: size.width * scale, height: (expanded ? size.height : 40) * scale)
        .notchBackground(appearance, style: style, shape: shape,
                         notchHeight: NotchLayout.previewNotchHeight * scale, glassRevealed: expanded)
        .clipShape(shape)
        .environment(\.colorScheme, .dark)
        .padding(.top, style == .pill ? 8 : 0)
        .frame(height: size.height * scale + 22, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Self.wallpaper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: appearance) {
            // Petite démonstration de l'animation choisie.
            expanded = false
            withAnimation(.spring(duration: max(0.15, spring.duration), bounce: spring.bounce)) { expanded = true }
        }
    }

    /// Fond d'écran de l'aperçu, coloré comme ceux de macOS.
    private static let wallpaper = LinearGradient(
        colors: [Color(red: 0.12, green: 0.16, blue: 0.42), Color(red: 0.5, green: 0.27, blue: 0.62),
                 Color(red: 0.96, green: 0.58, blue: 0.38)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// Choix de la mascotte : aperçu de ses humeurs, puis grille de tous les personnages.
private struct MascotPicker: View {
    @Binding var selection: MascotDesign

    private let columns = [GridItem(.adaptive(minimum: 74, maximum: 90), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // La mascotte choisie, dans toutes ses humeurs, sur fond noir comme dans l'encoche.
            HStack(spacing: 0) {
                ForEach(MascotMood.allCases, id: \.self) { mood in
                    LiveMascotView(design: selection, mood: mood, size: 40, reactsToTap: true)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 10)
            .background(.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(MascotDesign.allBoards, id: \.self) { design in
                    Button {
                        selection = design
                    } label: {
                        VStack(spacing: 2) {
                            MascotView(design: design, size: 30)
                                .frame(height: 42)
                            Text(verbatim: design.name)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(selection == design ? Color.accentColor : .clear, lineWidth: 2)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(Text(verbatim: design.name))
                }
            }
        }
        .padding(.vertical, 4)
    }
}
