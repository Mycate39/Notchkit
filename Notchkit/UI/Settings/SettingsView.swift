import SwiftUI

/// Pages de la fenêtre de réglages.
enum SettingsTab: Hashable {
    case general
    case appearance
    case layout
    /// Page d'un module (identifiant du module).
    case module(String)
    case about
}

/// Page affichée : permet d'ouvrir les réglages directement sur une page précise.
@MainActor
@Observable
final class SettingsRouter {
    var tab: SettingsTab = .general
}

/// Fenêtre de réglages façon Réglages Système : barre latérale à gauche, contenu à droite.
struct SettingsView: View {
    let settings: SettingsStore
    let manager: ModuleManager
    @Bindable var router: SettingsRouter

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<SettingsTab?>(get: { router.tab }, set: { if let tab = $0 { router.tab = tab } })) {
                Section {
                    sidebarRow("Général", symbol: "gearshape.fill", color: .gray).tag(SettingsTab.general)
                    sidebarRow("Apparence", symbol: "paintpalette.fill", color: .pink).tag(SettingsTab.appearance)
                    sidebarRow("Disposition", symbol: "rectangle.3.group.fill", color: .blue).tag(SettingsTab.layout)
                }
                Section("Modules") {
                    ForEach(manager.orderedDescriptors) { descriptor in
                        ModuleSidebarRow(descriptor: descriptor, isEnabled: manager.isEnabled(descriptor.id))
                            .tag(SettingsTab.module(descriptor.id))
                    }
                }
                Section {
                    sidebarRow("À propos", symbol: "info.circle.fill", color: .secondary).tag(SettingsTab.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 540)
    }

    @ViewBuilder
    private var detail: some View {
        switch router.tab {
        case .general: GeneralSettingsView(settings: settings).navigationTitle("Général")
        case .appearance: AppearanceSettingsView(settings: settings).navigationTitle("Apparence")
        case .layout: LayoutSettingsView(manager: manager).navigationTitle("Disposition")
        case let .module(id):
            if let descriptor = manager.orderedDescriptors.first(where: { $0.id == id }) {
                ModuleDetailView(descriptor: descriptor, manager: manager).navigationTitle(Text(descriptor.name))
            }
        case .about: AboutSettingsView().navigationTitle("À propos")
        }
    }

    private func sidebarRow(_ title: LocalizedStringKey, symbol: String, color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            SidebarIcon(symbol: symbol, color: color)
        }
    }
}

/// Icône carrée colorée, comme dans les Réglages Système.
private struct SidebarIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        if symbol == ClaudeMark.symbolName {
            // Étoile de Claude en terre cuite sur fond crème.
            ClaudeMarkShape()
                .fill(ClaudeMark.color)
                .padding(size * 0.16)
                .frame(width: size, height: size)
                .background(ClaudeMark.background, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        }
    }
}

private struct ModuleSidebarRow: View {
    let descriptor: ModuleDescriptor
    let isEnabled: Bool

    var body: some View {
        Label {
            HStack {
                Text(descriptor.name)
                Spacer()
                if isEnabled {
                    Circle().fill(.green).frame(width: 6, height: 6)
                        .help("Activé")
                }
            }
        } icon: {
            SidebarIcon(symbol: descriptor.systemImage, color: ModuleStyle.color(for: descriptor.category))
        }
    }
}

/// Couleur associée à chaque catégorie de modules.
enum ModuleStyle {
    static func color(for category: ModuleCategory) -> Color {
        switch category {
        case .media: .red
        case .system: .indigo
        case .widgets: .orange
        case .productivity: .teal
        }
    }
}

/// Page d'un module : en-tête (icône, description, interrupteur) puis ses réglages.
private struct ModuleDetailView: View {
    let descriptor: ModuleDescriptor
    let manager: ModuleManager

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    SidebarIcon(symbol: descriptor.systemImage, color: ModuleStyle.color(for: descriptor.category), size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(descriptor.name).font(.title2.bold())
                            if descriptor.tier == .pro {
                                Text("PRO")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(.tint, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                        Text(descriptor.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("Activer", isOn: Binding(
                        get: { manager.isEnabled(descriptor.id) },
                        set: { manager.setEnabled($0, for: descriptor.id) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!manager.isUnlocked(descriptor))
                }
                .padding(.vertical, 4)
            }

            if let module = manager.module(for: descriptor.id) {
                if let options = module.settingsView() {
                    Section("Réglages") {
                        options
                    }
                }
                if descriptor.providesWidget {
                    Section("Dans l'encoche") {
                        LabeledContent("Taille du widget") {
                            Picker("Taille", selection: Binding(
                                get: { manager.size(for: descriptor.id) },
                                set: { manager.setSize($0, for: descriptor.id) }
                            )) {
                                ForEach(WidgetSize.allCases) { size in
                                    Text(size.title).tag(size)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 300)
                        }
                        if let position = manager.position(of: descriptor.id) {
                            LabeledContent("Emplacement", value: String(localized: "Page \(position.page + 1), position \(position.index + 1)"))
                        }
                    }
                } else {
                    Section {
                        Text("Ce module fonctionne en arrière-plan, sans carte dans l'encoche.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    Text("Activez le module pour afficher ses réglages.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Général

private struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore

    @State private var screens: [ScreenOption] = ScreenOption.connected()
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var autoUpdate = Updater.shared.automaticallyChecks

    var body: some View {
        Form {
            Section("Écran") {
                Picker("Afficher l'encoche sur", selection: $settings.settings.screenSelection) {
                    Text("Écran principal").tag(ScreenSelection.primary)
                    ForEach(screens) { screen in
                        Text(screen.label).tag(screen.selection)
                    }
                    // L'écran choisi n'est plus branché : on le garde dans la liste pour l'indiquer.
                    if case let .specific(id, name) = settings.settings.screenSelection,
                       !screens.contains(where: { $0.id == id }) {
                        Text("\(name) (débranché)").tag(settings.settings.screenSelection)
                    }
                }
                Toggle("Ne pas cacher les menus de l'app active", isOn: $settings.settings.avoidAppMenus)
                Text("Sur un écran sans encoche, l'encoche se décale vers la droite si elle couvre les menus de l'app au premier plan. Nécessite l'autorisation Accessibilité (Réglages Système > Confidentialité et sécurité > Accessibilité).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Survol") {
                LabeledContent("Délai d'ouverture") {
                    HStack {
                        Slider(value: $settings.settings.hoverOpenDelay, in: 0...0.6, step: 0.02)
                        Text(settings.settings.hoverOpenDelay, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                        Text("s")
                    }
                }
                LabeledContent("Délai de fermeture") {
                    HStack {
                        Slider(value: $settings.settings.hoverCloseDelay, in: 0.1...1.5, step: 0.05)
                        Text(settings.settings.hoverCloseDelay, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                        Text("s")
                    }
                }
            }

            Section("Retour haptique") {
                Toggle("Retour haptique du trackpad", isOn: $settings.settings.hapticsEnabled)
                Text("Un léger clic à l'ouverture de l'encoche, au changement de page, aux alertes et à chaque cran de volume (trackpad Force Touch).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Système") {
                Toggle("Lancer Notchkit à l'ouverture de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        launchError = LaunchAtLogin.setEnabled(newValue)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Mises à jour") {
                Toggle("Rechercher automatiquement les mises à jour", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { _, newValue in Updater.shared.automaticallyChecks = newValue }
                    .disabled(!Updater.shared.isAvailable)
                Button("Rechercher maintenant…") { Updater.shared.checkForUpdates() }
                    .disabled(!Updater.shared.isAvailable)
                Text(Updater.shared.isAvailable
                     ? "Notchkit vérifie une fois par jour si une nouvelle version est disponible sur GitHub, puis l'installe et redémarre après votre accord."
                     : "Les mises à jour automatiques ne sont disponibles que dans les versions publiées.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle("Simuler une encoche", isOn: $settings.settings.simulateNotch)
            } header: {
                Text("Développement")
            } footer: {
                Text("Affiche une fausse encoche sur les écrans qui n'en ont pas, pour tester le rendu.")
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = ScreenOption.connected()
        }
    }
}

/// Écran proposé dans le sélecteur.
private struct ScreenOption: Identifiable {
    let id: String
    let name: String
    let hasNotch: Bool

    var selection: ScreenSelection { .specific(id: id, name: name) }
    var label: String { hasNotch ? String(localized: "\(name) (avec encoche)") : name }

    @MainActor
    static func connected() -> [ScreenOption] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.notchkitID else { return nil }
            return ScreenOption(id: id, name: screen.localizedName, hasNotch: screen.hasNotch)
        }
    }
}

// MARK: - À propos

private struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.topthird.inset.filled")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Notchkit")
                .font(.title.bold())
            Text("Version \(version)")
                .foregroundStyle(.secondary)
            Text("Transformez l'encoche de votre Mac en une zone interactive et modulaire.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            Button("Licences des composants tiers") {
                showsLicenses = true
            }
            .buttonStyle(.link)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showsLicenses) {
            ThirdPartyLicensesView()
        }
    }

    @State private var showsLicenses = false
}

/// Mentions de licence exigées par les composants tiers intégrés à l'app.
private struct ThirdPartyLicensesView: View {
    @Environment(\.dismiss) private var dismiss

    private var mediaRemoteLicense: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Licences des composants tiers")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MediaRemoteAdapter")
                        .font(.subheadline.bold())
                    Text("https://github.com/ungive/mediaremote-adapter")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(mediaRemoteLicense)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)

                    Divider().padding(.vertical, 6)

                    Text("Open-Meteo")
                        .font(.subheadline.bold())
                    Text("https://open-meteo.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Données météo fournies par Open-Meteo.com, sous licence Creative Commons Attribution 4.0 (CC BY 4.0).")
                        .font(.system(size: 11))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 380)
    }
}
