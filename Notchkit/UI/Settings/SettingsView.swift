import SwiftUI

/// Pages de la fenêtre de réglages.
enum SettingsTab: Hashable {
    case general
    case appearance
    case layout
    /// Liste de tous les widgets et modules.
    case widgets
    /// Page d'un module (identifiant du module), ouverte depuis la liste des widgets.
    case module(String)
    case permissions
    case about
}

/// Page affichée : permet d'ouvrir les réglages directement sur une page précise.
@MainActor
@Observable
final class SettingsRouter {
    var tab: SettingsTab = .general {
        didSet {
            guard !isTravelling, tab != oldValue else { return }
            backStack.append(oldValue)
            forwardStack.removeAll()
        }
    }
    /// Historique des pages, comme les flèches Précédent / Suivant des Réglages Système.
    private(set) var backStack: [SettingsTab] = []
    private(set) var forwardStack: [SettingsTab] = []
    @ObservationIgnored private var isTravelling = false

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        travel(to: previous) { forwardStack.append($0) }
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        travel(to: next) { backStack.append($0) }
    }

    private func travel(to destination: SettingsTab, keeping current: (SettingsTab) -> Void) {
        current(tab)
        isTravelling = true
        tab = destination
        isTravelling = false
    }
}

extension View {
    /// Flèches Précédent / Suivant groupées dans une capsule, comme dans les Réglages Système.
    func settingsHistory(_ router: SettingsRouter) -> some View {
        toolbar {
            ToolbarItem(placement: .navigation) {
                ControlGroup {
                    Button { router.goBack() } label: { Label("Précédent", systemImage: "chevron.left") }
                        .disabled(!router.canGoBack)
                        .keyboardShortcut("[", modifiers: .command)
                    Button { router.goForward() } label: { Label("Suivant", systemImage: "chevron.right") }
                        .disabled(!router.canGoForward)
                        .keyboardShortcut("]", modifiers: .command)
                }
                .controlGroupStyle(.navigation)
            }
        }
    }
}

/// Fenêtre de réglages façon Réglages Système : barre latérale à gauche, contenu à droite.
struct SettingsView: View {
    let settings: SettingsStore
    let manager: ModuleManager
    @Bindable var router: SettingsRouter
    @State private var permissions = PermissionCenter()

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<SettingsTab?>(get: { router.tab.sidebarTab }, set: { if let tab = $0 { router.tab = tab } })) {
                Section {
                    sidebarRow("Général", symbol: "gearshape.fill", color: .gray).tag(SettingsTab.general)
                    sidebarRow("Apparence", symbol: "paintpalette.fill", color: .pink).tag(SettingsTab.appearance)
                    sidebarRow("Disposition", symbol: "rectangle.3.group.fill", color: .blue).tag(SettingsTab.layout)
                    sidebarRow("Widgets", symbol: "square.grid.2x2.fill", color: .orange).tag(SettingsTab.widgets)
                }
                Section {
                    sidebarRow("Autorisations", symbol: "hand.raised.fill", color: .blue).tag(SettingsTab.permissions)
                    sidebarRow("À propos", symbol: "info.circle.fill", color: .secondary).tag(SettingsTab.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            // Style des icônes de macOS : relu à l'ouverture et au retour des Réglages Système.
            .onAppear { SystemIconAppearance.shared.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                SystemIconAppearance.shared.refresh()
            }
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 540)
    }

    @ViewBuilder
    private var detail: some View {
        switch router.tab {
        case .general: GeneralSettingsView(settings: settings).navigationTitle("Général").settingsHistory(router)
        case .appearance: AppearanceSettingsView(settings: settings).navigationTitle("Apparence").settingsHistory(router)
        case .layout: LayoutSettingsView(manager: manager).navigationTitle("Disposition").settingsHistory(router)
        // La liste des widgets a sa propre pile de navigation, qui remplace la barre d'outils :
        // elle pose les flèches sur chacune de ses pages.
        case .widgets, .module: WidgetsSettingsView(manager: manager, router: router)
        case .permissions: PermissionsSettingsView(center: permissions).navigationTitle("Autorisations").settingsHistory(router)
        case .about: AboutSettingsView().navigationTitle("À propos").settingsHistory(router)
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
/// Style des icônes choisi dans Réglages Système › Apparence (« Style des icônes et widgets »),
/// lu dans les préférences globales (`AppleIconAppearanceTheme`, clé non documentée) :
/// aucune valeur = Par défaut, `RegularDark` = Sombre, `ClearLight` / `ClearDark` = Transparent,
/// `…Automatic` = selon le mode clair ou sombre. Le style teinté garde les icônes normales.
enum SystemIconStyle: Equatable {
    case standard
    case dark
    case clear(dark: Bool)

    static let defaultsKey = "AppleIconAppearanceTheme"

    /// Fonction pure, testée.
    static func from(theme: String?, systemIsDark: Bool) -> SystemIconStyle {
        guard let theme, !theme.isEmpty else { return .standard }
        let automatic = theme.hasSuffix("Automatic")
        let dark = theme.hasSuffix("Dark") || (automatic && systemIsDark)
        if theme.hasPrefix("Clear") { return .clear(dark: dark) }
        if theme.hasPrefix("Regular") { return dark ? .dark : .standard }
        return .standard
    }
}

/// Valeur en vigueur du style d'icônes de macOS, relue quand Notchkit repasse au premier plan
/// (on revient des Réglages Système).
@MainActor
@Observable
final class SystemIconAppearance {
    static let shared = SystemIconAppearance()
    private(set) var theme: String?

    private init() { refresh() }

    func refresh() {
        let value = UserDefaults.standard.string(forKey: SystemIconStyle.defaultsKey)
        if value != theme { theme = value }
    }
}

/// Icône carrée des réglages (barre latérale, widgets, autorisations), au style d'icônes de macOS
/// (par défaut, sombre ou transparent).
struct SidebarIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20
    @Environment(\.colorScheme) private var colorScheme

    private var style: SystemIconStyle {
        SystemIconStyle.from(theme: SystemIconAppearance.shared.theme, systemIsDark: colorScheme == .dark)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
        if symbol == ClaudeMark.symbolName {
            // Étoile de Claude en terre cuite sur fond crème (sombre ou transparent selon le style).
            ClaudeMarkShape()
                .fill(ClaudeMark.color)
                .padding(size * 0.16)
                .frame(width: size, height: size)
                .background(background(ClaudeMark.background), in: shape)
                .overlay { outline(shape) }
        } else {
            // Symbole ajusté dans une boîte fixe : les symboles larges (batterie, traduction)
            // ne débordent plus du carré et les compacts ne paraissent plus minuscules.
            Image(systemName: symbol)
                .resizable()
                .fontWeight(.semibold)
                .scaledToFit()
                .frame(width: size * 0.7, height: size * 0.6)
                .foregroundStyle(glyph)
                .frame(width: size, height: size)
                .background(background(color), in: shape)
                .overlay { outline(shape) }
        }
    }

    /// Fond : couleur pleine par défaut, gris très sombre en mode sombre, verre en transparent.
    private func background(_ base: Color) -> AnyShapeStyle {
        switch style {
        case .standard: AnyShapeStyle(base.gradient)
        case .dark: AnyShapeStyle(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.11)],
                                                 startPoint: .top, endPoint: .bottom))
        case .clear(let dark): AnyShapeStyle(.white.opacity(dark ? 0.1 : 0.4))
        }
    }

    /// Symbole : blanc par défaut, de la couleur de l'icône en sombre, blanc adouci en transparent.
    private var glyph: AnyShapeStyle {
        switch style {
        case .standard: AnyShapeStyle(.white)
        case .dark: AnyShapeStyle(color.gradient)
        case .clear(let dark): AnyShapeStyle(.white.opacity(dark ? 0.85 : 0.95))
        }
    }

    /// Fin liseré clair des icônes sombres et transparentes.
    @ViewBuilder
    private func outline(_ shape: RoundedRectangle) -> some View {
        if style != .standard {
            shape.strokeBorder(.white.opacity(style == .dark ? 0.12 : 0.3), lineWidth: 0.5)
        }
    }
}

extension SettingsTab {
    /// Entrée de la barre latérale sélectionnée : la page d'un module reste sous « Widgets ».
    var sidebarTab: SettingsTab {
        if case .module = self { return .widgets }
        return self
    }
}

/// Onglet « Widgets » : tous les modules, groupés par catégorie, chacun avec son interrupteur ;
/// un clic ouvre ses réglages (bouton retour pour revenir à la liste).
struct WidgetsSettingsView: View {
    let manager: ModuleManager
    @Bindable var router: SettingsRouter

    /// Le module ouvert est porté par la page des réglages : un lien direct vers un module
    /// (menu contextuel d'un widget) ouvre la liste déjà poussée sur ce module.
    private var path: Binding<[String]> {
        Binding(
            get: { if case let .module(id) = router.tab { [id] } else { [] } },
            set: { router.tab = $0.last.map(SettingsTab.module) ?? .widgets }
        )
    }

    var body: some View {
        NavigationStack(path: path) {
            Form {
                ForEach(ModuleCategory.allCases) { category in
                    let descriptors = manager.orderedDescriptors.filter { $0.category == category && $0.companionOf == nil }
                    if !descriptors.isEmpty {
                        Section(String(localized: category.title)) {
                            ForEach(descriptors) { descriptor in
                                WidgetRow(descriptor: descriptor, manager: manager)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Widgets")
            .settingsHistory(router)
            .navigationDestination(for: String.self) { id in
                if let descriptor = manager.orderedDescriptors.first(where: { $0.id == id }) {
                    ModuleDetailView(descriptor: descriptor, manager: manager)
                        .navigationTitle(Text(descriptor.name))
                        // Retour à la liste : flèche Précédent de la barre d'outils (⌘[).
                        .navigationBarBackButtonHidden(true)
                        .settingsHistory(router)
                }
            }
        }
    }
}

/// Ligne d'un module : icône, nom et description ouvrent ses réglages ; l'interrupteur l'active.
private struct WidgetRow: View {
    let descriptor: ModuleDescriptor
    let manager: ModuleManager

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink(value: descriptor.id) {
                HStack(spacing: 10) {
                    SidebarIcon(symbol: descriptor.systemImage, color: ModuleStyle.color(for: descriptor.category), size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(descriptor.name)
                        Text(descriptor.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("Activer", isOn: Binding(
                get: { manager.isEnabled(descriptor.id) },
                set: { manager.setEnabled($0, for: descriptor.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!manager.isUnlocked(descriptor))
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
                                    .font(.system(size: 10, weight: .bold))
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
                if descriptor.fullPage {
                    Section("Dans l'encoche") {
                        LabeledContent("Taille du widget", value: String(localized: "Pleine page"))
                        if let position = manager.position(of: descriptor.id) {
                            LabeledContent("Emplacement", value: String(localized: "Page \(position.page + 1), position \(position.index + 1)"))
                        }
                    }
                } else if descriptor.providesWidget {
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
    @State private var receivesBetas = Updater.shared.receivesBetas

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
                Toggle("Masquer l'encoche pendant une vidéo en plein écran", isOn: $settings.settings.hidesInFullScreen)
                Text("L'encoche disparaît tant qu'une vidéo (YouTube, Netflix, QuickTime…) est lue en plein écran sur son écran, puis revient.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Ne pas cacher les menus de l'app active", isOn: $settings.settings.avoidAppMenus)
                Text("Sur un écran sans encoche, l'encoche se décale vers la droite si elle couvre les menus de l'app au premier plan. Sur une vraie encoche, l'activité compacte se rétrécit, ou se masque, pour laisser les menus visibles. Nécessite l'autorisation Accessibilité (Réglages Système > Confidentialité et sécurité > Accessibilité).")
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
                // Valeurs d'origine (celles d'un fichier de réglages neuf).
                let defaults = AppSettings()
                HStack {
                    Spacer()
                    Button("Rétablir les valeurs par défaut") {
                        settings.settings.hoverOpenDelay = defaults.hoverOpenDelay
                        settings.settings.hoverCloseDelay = defaults.hoverCloseDelay
                    }
                    .disabled(settings.settings.hoverOpenDelay == defaults.hoverOpenDelay
                              && settings.settings.hoverCloseDelay == defaults.hoverCloseDelay)
                }
            }

            Section("Retour haptique") {
                Toggle("Retour haptique du trackpad", isOn: $settings.settings.hapticsEnabled)
                Text("Un léger clic quand vous ouvrez l'encoche, changez de page, réglez le volume ou le minuteur, ou touchez une commande (trackpad Force Touch).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Système") {
                Toggle("Afficher Notchkit dans la barre des menus", isOn: $settings.settings.showsMenuBarIcon)
                if !settings.settings.showsMenuBarIcon {
                    Text("Pour revenir aux réglages : roue dentée de l'encoche dépliée, ou relancez Notchkit depuis le Finder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                Toggle("Recevoir les versions bêta", isOn: $receivesBetas)
                    .onChange(of: receivesBetas) { _, newValue in Updater.shared.receivesBetas = newValue }
                    .disabled(!Updater.shared.isAvailable)
                Button("Rechercher maintenant…") { Updater.shared.checkForUpdates() }
                    .disabled(!Updater.shared.isAvailable)
                Text(Updater.shared.isAvailable
                     ? "Notchkit vérifie une fois par jour si une nouvelle version est disponible sur GitHub, puis l'installe et redémarre après votre accord. Les versions bêta arrivent plus tôt avec les nouveautés, mais peuvent contenir des défauts."
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
