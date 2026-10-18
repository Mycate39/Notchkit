import AppKit
import SwiftUI
import Observation

/// Reconnaît un jeu d'après sa catégorie App Store ou son emplacement (logique pure, testée).
enum GameDetector {
    static func isGame(category: String?, path: String?) -> Bool {
        if let category, category.lowercased().contains("games") { return true }
        // Jeux Steam : installés dans « steamapps/common ».
        if let path, path.lowercased().contains("/steamapps/common/") { return true }
        return false
    }

    @MainActor
    static func isGame(_ app: NSRunningApplication) -> Bool {
        let bundle = app.bundleURL.flatMap(Bundle.init(url:))
        return isGame(category: bundle?.infoDictionary?["LSApplicationCategoryType"] as? String,
                      path: app.bundleURL?.path ?? app.executableURL?.path)
    }
}

/// Mode jeu : l'encoche se fait discrète pendant une partie (ni ouverture au survol, ni alertes,
/// ni bulles) et affiche autour d'elle la charge du processeur et de la carte graphique.
/// Il s'active tout seul quand un jeu passe au premier plan, ou à la main.
@MainActor
@Observable
final class GameModeModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "gamemode",
        name: "Mode jeu",
        summary: "Pendant une partie, l'encoche se fait discrète et affiche la charge du processeur, de la carte graphique et l'état thermique.",
        systemImage: "gamecontroller.fill",
        category: .system,
        tier: .free,
        defaultEnabled: false,
        providesWidget: false
    )

    private enum Keys {
        static let automatic = "module.gamemode.automatic"
        static let showsStats = "module.gamemode.showsStats"
    }

    @ObservationIgnored let context: ModuleContext
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    /// Activation automatique quand un jeu est au premier plan.
    var automatic: Bool {
        didSet { UserDefaults.standard.set(automatic, forKey: Keys.automatic); update() }
    }
    /// Charges et état thermique autour de l'encoche.
    var showsStats: Bool {
        didSet { UserDefaults.standard.set(showsStats, forKey: Keys.showsStats) }
    }
    /// Forcé à la main (barre des menus) : `nil` = automatique.
    private(set) var manualOverride: Bool?
    /// Un jeu est au premier plan.
    private(set) var gameInFront = false
    private(set) var isActive = false
    private var samplerAcquired = false

    init(context: ModuleContext) {
        self.context = context
        let defaults = UserDefaults.standard
        automatic = defaults.object(forKey: Keys.automatic) as? Bool ?? true
        showsStats = defaults.object(forKey: Keys.showsStats) as? Bool ?? true
    }

    func start() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.frontmostChanged(app) }
        }
        frontmostChanged(NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        activationObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
        activationObserver = nil
        manualOverride = nil
        setActive(false)
    }

    private func frontmostChanged(_ app: NSRunningApplication?) {
        gameInFront = app.map(GameDetector.isGame) ?? false
        update()
    }

    /// Active ou coupe le mode jeu à la main ; `nil` revient au mode automatique.
    func setManual(_ active: Bool?) {
        manualOverride = active
        update()
    }

    /// Bascule depuis la barre des menus.
    func toggle() {
        setManual(isActive ? false : true)
    }

    static func shouldBeActive(manual: Bool?, automatic: Bool, gameInFront: Bool) -> Bool {
        manual ?? (automatic && gameInFront)
    }

    private func update() {
        // Un jeu quitte le premier plan : le choix manuel « coupé » ne s'applique qu'à cette partie.
        if manualOverride == false && !gameInFront { manualOverride = nil }
        setActive(Self.shouldBeActive(manual: manualOverride, automatic: automatic, gameInFront: gameInFront))
    }

    private func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        context.setQuietMode(active)
        if active && !samplerAcquired {
            SystemSampler.shared.acquire()
            samplerAcquired = true
        } else if !active && samplerAcquired {
            SystemSampler.shared.release()
            samplerAcquired = false
        }
    }

    // MARK: Encoche repliée

    var compactPriority: ModulePriority { isActive && showsStats ? .high : .none }
    var compactSideWidth: CGFloat { 62 }

    func compactLeading() -> AnyView? {
        guard isActive, showsStats else { return nil }
        return AnyView(GameStat(symbol: "gamecontroller.fill", value: SystemSampler.shared.snapshot.cpuTotal, label: "CPU"))
    }

    func compactTrailing() -> AnyView? {
        guard isActive, showsStats else { return nil }
        return AnyView(GameStat(symbol: GameThermal.symbol, value: SystemSampler.shared.snapshot.gpu, label: "GPU",
                                tint: GameThermal.color))
    }

    /// Pas de widget : le mode jeu ne s'affiche qu'autour de l'encoche repliée.
    func expandedView() -> AnyView { AnyView(EmptyView()) }

    func settingsView() -> AnyView? {
        AnyView(GameModeSettingsView(module: self))
    }
}

/// État thermique du Mac (macOS ne donne pas de température en degrés avec ses outils publics).
enum GameThermal {
    static var symbol: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "thermometer.low"
        case .fair: "thermometer.medium"
        case .serious, .critical: "thermometer.high"
        @unknown default: "thermometer.medium"
        }
    }

    static var color: Color {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .white.opacity(0.7)
        case .fair: StandBy.amber
        case .serious, .critical: Color(red: 1, green: 0.32, blue: 0.28)
        @unknown default: .white.opacity(0.7)
        }
    }
}

/// Une mesure autour de l'encoche : icône et pourcentage.
private struct GameStat: View {
    let symbol: String
    let value: Double?
    let label: String
    var tint: Color = .white.opacity(0.7)

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(value.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .help(Text(verbatim: label))
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

private struct GameModeSettingsView: View {
    @Bindable var module: GameModeModule

    var body: some View {
        Toggle("S'activer quand un jeu est au premier plan", isOn: $module.automatic)
        Text("Les jeux sont reconnus à leur catégorie App Store et aux jeux Steam. Vous pouvez aussi l'activer ou le couper depuis l'icône de Notchkit dans la barre des menus.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Toggle("Afficher la charge du processeur et de la carte graphique", isOn: $module.showsStats)
        Text("Pendant une partie, l'encoche ne s'ouvre plus au survol et les alertes et bulles sont mises en pause.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
