import SwiftUI

/// Onglets de la fenêtre de réglages.
enum SettingsTab: Hashable {
    case general
    case layout
    case modules
    case about
}

/// Onglet affiché : permet d'ouvrir les réglages directement sur un onglet précis.
@MainActor
@Observable
final class SettingsRouter {
    var tab: SettingsTab = .general
}

/// Écran de réglages, enrichi au fil des étapes.
struct SettingsView: View {
    let settings: SettingsStore
    let manager: ModuleManager
    @Bindable var router: SettingsRouter

    var body: some View {
        TabView(selection: $router.tab) {
            GeneralSettingsView(settings: settings)
                .tabItem { Label("Général", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            LayoutSettingsView(manager: manager)
                .tabItem { Label("Disposition", systemImage: "rectangle.3.group") }
                .tag(SettingsTab.layout)

            ModulesSettingsView(manager: manager)
                .tabItem { Label("Modules", systemImage: "square.grid.2x2") }
                .tag(SettingsTab.modules)

            AboutSettingsView()
                .tabItem { Label("À propos", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 620, height: 500)
    }
}

// MARK: - Général

private struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore

    @State private var screens: [ScreenOption] = ScreenOption.connected()
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

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

// MARK: - Modules

private struct ModulesSettingsView: View {
    let manager: ModuleManager

    var body: some View {
        Form {
            ForEach(ModuleCategory.allCases) { category in
                let descriptors = manager.orderedDescriptors.filter { $0.category == category }
                if !descriptors.isEmpty {
                    Section {
                        ForEach(descriptors) { descriptor in
                            ModuleRow(descriptor: descriptor, manager: manager)
                        }
                    } header: {
                        Text(category.title)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModuleRow: View {
    let descriptor: ModuleDescriptor
    let manager: ModuleManager

    var body: some View {
        let unlocked = manager.isUnlocked(descriptor)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: descriptor.systemImage)
                    .font(.system(size: 16))
                    .frame(width: 28, height: 28)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(descriptor.name)
                        if descriptor.tier == .pro {
                            Text("PRO")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.tint, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    Text(descriptor.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Activer", isOn: Binding(
                    get: { manager.isEnabled(descriptor.id) },
                    set: { manager.setEnabled($0, for: descriptor.id) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!unlocked)
            }

            // Réglages propres au module, visibles seulement s'il est activé.
            if let module = manager.module(for: descriptor.id), let options = module.settingsView() {
                options
                    .padding(.leading, 40)
            }
        }
        .padding(.vertical, 2)
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
