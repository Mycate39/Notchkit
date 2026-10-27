import AppKit
import SwiftUI
import Observation

/// Reconnaît un jeu d'après sa catégorie App Store, la clé du mode jeu ou son emplacement (logique pure, testée).
enum GameDetector {
    static func isGame(category: String?, path: String?, supportsGameMode: Bool = false) -> Bool {
        if supportsGameMode { return true }
        if let category, category.lowercased().contains("games") { return true }
        // Jeux Steam : installés dans « steamapps/common ».
        if let path, path.lowercased().contains("/steamapps/common/") { return true }
        return false
    }

    @MainActor
    static func isGame(_ app: NSRunningApplication) -> Bool {
        let info = app.bundleURL.flatMap(Bundle.init(url:))?.infoDictionary
        return isGame(category: info?["LSApplicationCategoryType"] as? String,
                      path: app.bundleURL?.path ?? app.executableURL?.path,
                      supportsGameMode: info?["LSSupportsGameMode"] as? Bool ?? false)
    }
}

/// Mode jeu : l'encoche se fait discrète pendant une partie (ni ouverture au survol, ni alertes,
/// ni bulles) et affiche les images par seconde du jeu.
/// Il s'active en même temps que le mode jeu de macOS (un jeu en plein écran au premier plan), ou à la main.
@MainActor
@Observable
final class GameModeModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "gamemode",
        name: "Mode jeu",
        summary: "Quand un jeu passe en plein écran, comme le mode jeu de macOS, l'encoche se fait discrète et affiche les images par seconde.",
        systemImage: "gamecontroller.fill",
        category: .system,
        tier: .free,
        defaultEnabled: false,
        providesWidget: false
    )

    private enum Keys {
        static let automatic = "module.gamemode.automatic"
        static let showsFPS = "module.gamemode.showsFPS"
    }

    /// Fréquence de rafraîchissement du compteur et de la détection du plein écran.
    static let fpsRefreshInterval: TimeInterval = 0.5
    static let fullScreenCheckInterval: TimeInterval = 1

    @ObservationIgnored let context: ModuleContext
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let meter = FrameRateMeter()
    @ObservationIgnored private var fpsTimer: Timer?
    @ObservationIgnored private var fullScreenTimer: Timer?
    @ObservationIgnored private var frontApp: NSRunningApplication?
    @ObservationIgnored private var frontIsGame = false
    @ObservationIgnored private var measuredPID: pid_t?

    /// Activation automatique avec le mode jeu de macOS.
    var automatic: Bool {
        didSet { UserDefaults.standard.set(automatic, forKey: Keys.automatic); update() }
    }
    /// Images par seconde à droite de l'encoche.
    var showsFPS: Bool {
        didSet { UserDefaults.standard.set(showsFPS, forKey: Keys.showsFPS); updateMeasuring() }
    }
    /// Forcé à la main (barre des menus) : `nil` = automatique.
    private(set) var manualOverride: Bool?
    /// Un jeu en plein écran est au premier plan.
    private(set) var gameInFront = false
    private(set) var isActive = false
    /// Dernière mesure ; `nil` sans autorisation d'enregistrement de l'écran.
    private(set) var fps: Int?

    init(context: ModuleContext) {
        self.context = context
        let defaults = UserDefaults.standard
        automatic = defaults.object(forKey: Keys.automatic) as? Bool ?? true
        showsFPS = defaults.object(forKey: Keys.showsFPS) as? Bool ?? true
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.frontmostChanged(app) }
            },
            // Passage en plein écran natif : nouveau bureau.
            center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkFullScreen() }
            },
        ]
        frontmostChanged(NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        fullScreenTimer?.invalidate()
        fullScreenTimer = nil
        manualOverride = nil
        setActive(false)
    }

    private func frontmostChanged(_ app: NSRunningApplication?) {
        frontApp = app
        frontIsGame = app.map(GameDetector.isGame) ?? false
        // Les jeux sans plein écran natif (fenêtre sans bordure) ne changent pas de bureau : on vérifie souvent.
        fullScreenTimer?.invalidate()
        fullScreenTimer = nil
        if frontIsGame {
            fullScreenTimer = Timer.scheduledTimer(withTimeInterval: Self.fullScreenCheckInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkFullScreen() }
            }
        }
        checkFullScreen()
        updateMeasuring()
    }

    private func checkFullScreen() {
        let inFront = frontIsGame && (frontApp.map { FullScreenDetector.isFullScreen(pid: $0.processIdentifier) } ?? false)
        guard inFront != gameInFront else { return }
        gameInFront = inFront
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
        updateMeasuring()
    }

    // MARK: Images par seconde

    static var canMeasure: Bool { !AutomatedRun.isActive && CGPreflightScreenCaptureAccess() }

    /// Mesure l'app au premier plan tant que le mode jeu est actif et le compteur affiché.
    private func updateMeasuring() {
        let pid = isActive && showsFPS && Self.canMeasure ? frontApp?.processIdentifier : nil
        guard pid != measuredPID else { return }
        measuredPID = pid
        fpsTimer?.invalidate()
        fpsTimer = nil
        meter.stop()
        guard let pid else { fps = nil; return }
        fps = 0
        let meter = meter
        Task { try? await meter.start(pid: pid) }
        fpsTimer = Timer.scheduledTimer(withTimeInterval: Self.fpsRefreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.measuredPID != nil else { return }
                let value = self.meter.currentFPS
                if value != self.fps { self.fps = value }
            }
        }
    }

    /// Demande l'autorisation d'enregistrer l'écran ; si macOS ne la propose plus, ouvre les Réglages Système.
    func requestScreenCapture() {
        if !CGRequestScreenCaptureAccess() { PermissionCenter.open(.screenRecording) }
        updateMeasuring()
    }

    // MARK: Encoche repliée

    var compactPriority: ModulePriority { isActive && showsFPS ? .high : .none }

    func compactLeading() -> AnyView? {
        guard isActive, showsFPS else { return nil }
        return AnyView(Image(systemName: "gamecontroller.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75)))
    }

    func compactTrailing() -> AnyView? {
        guard isActive, showsFPS, let fps else { return nil }
        return AnyView(FPSCounter(fps: fps))
    }

    /// Pas de widget : le mode jeu ne s'affiche qu'autour de l'encoche repliée.
    func expandedView() -> AnyView { AnyView(EmptyView()) }

    func settingsView() -> AnyView? {
        AnyView(GameModeSettingsView(module: self))
    }
}

/// Compteur d'images par seconde : ambre sous 30, signe d'une partie qui saccade.
struct FPSCounter: View {
    let fps: Int

    static let lowThreshold = 30

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(fps, format: .number)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(fps < Self.lowThreshold ? StandBy.amber : .white)
                .contentTransition(.numericText(value: Double(fps)))
            Text(verbatim: "FPS")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
        }
        .lineLimit(1)
        .fixedSize()
        .animation(.easeOut(duration: 0.25), value: fps)
    }
}

private struct GameModeSettingsView: View {
    @Bindable var module: GameModeModule
    @State private var canMeasure = GameModeModule.canMeasure

    var body: some View {
        Toggle("S'activer avec le mode jeu de macOS", isOn: $module.automatic)
        Text("Comme le mode jeu de macOS : quand un jeu passe en plein écran au premier plan. Vous pouvez aussi l'activer ou le couper depuis l'icône de Notchkit dans la barre des menus.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Toggle("Afficher les images par seconde", isOn: $module.showsFPS)
        if module.showsFPS && !canMeasure {
            LabeledContent {
                Button("Demander l'accès…") {
                    module.requestScreenCapture()
                    canMeasure = GameModeModule.canMeasure
                }
            } label: {
                Text("Le compteur a besoin de l'autorisation Enregistrement de l'écran. L'écran n'est jamais enregistré : Notchkit compte seulement les images affichées.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Text("Pendant une partie, l'encoche ne s'ouvre plus au survol et les alertes et bulles sont mises en pause.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear { canMeasure = GameModeModule.canMeasure }
    }
}

#if DEBUG
extension GameModeModule {
    /// Mode jeu imposé (tournages de démonstration), avec un compteur d'images fictif.
    func debugSet(active: Bool, fps: Int?) {
        isActive = active
        context.setQuietMode(active)
        self.fps = active ? fps : nil
    }
}
#endif
