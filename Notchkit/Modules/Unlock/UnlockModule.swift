import AppKit
import SwiftUI
import Observation

/// Demandes d'authentification affichées par macOS.
enum AuthPrompt: Equatable, Sendable {
    /// Demande Touch ID d'une app (LocalAuthentication).
    case touchID
    /// Fenêtre de mot de passe (administrateur, trousseau…).
    case password

    /// Composant système qui affiche la demande.
    init?(bundleIdentifier: String?) {
        switch bundleIdentifier {
        case "com.apple.LocalAuthentication.UIAgent", "com.apple.LocalAuthenticationRemoteService": self = .touchID
        case "com.apple.SecurityAgent": self = .password
        default: return nil
        }
    }
}

/// Module Déverrouillage : animations façon Face ID.
/// - au déverrouillage du Mac (macOS ne dit pas si c'était Touch ID ou le mot de passe :
///   une seule animation, jouée juste après, car rien ne peut s'afficher sur l'écran verrouillé) ;
/// - pendant une demande Touch ID ;
/// - pendant une demande de mot de passe.
/// Détection par notifications publiques (session déverrouillée, app passée au premier plan).
@MainActor
@Observable
final class UnlockModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "unlock",
        name: "Déverrouillage",
        summary: "Animations façon Face ID au déverrouillage, pendant Touch ID et pendant la saisie d'un mot de passe.",
        systemImage: "faceid",
        category: .system,
        tier: .free,
        defaultEnabled: true,
        providesWidget: false
    )

    var animateUnlock: Bool {
        didSet { UserDefaults.standard.set(animateUnlock, forKey: Keys.unlock) }
    }
    var animateTouchID: Bool {
        didSet { UserDefaults.standard.set(animateTouchID, forKey: Keys.touchID) }
    }
    var animatePassword: Bool {
        didSet { UserDefaults.standard.set(animatePassword, forKey: Keys.password) }
    }

    private enum Keys {
        static let unlock = "module.unlock.animateUnlock"
        static let touchID = "module.unlock.animateTouchID"
        static let password = "module.unlock.animatePassword"
    }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var activePrompt: (kind: AuthPrompt, alertID: UUID)?

    init(context: ModuleContext) {
        self.context = context
        let defaults = UserDefaults.standard
        animateUnlock = defaults.object(forKey: Keys.unlock) as? Bool ?? true
        animateTouchID = defaults.object(forKey: Keys.touchID) as? Bool ?? true
        animatePassword = defaults.object(forKey: Keys.password) as? Bool ?? true
    }

    func start() {
        guard observers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenUnlocked() }
        }))

        // Les demandes d'authentification passent au premier plan quand elles s'affichent.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                MainActor.assumeIsolated { self?.applicationAppeared(bundleID) }
            }))
        }
        for name in [NSWorkspace.didDeactivateApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                MainActor.assumeIsolated { self?.applicationDisappeared(bundleID) }
            }))
        }
    }

    func stop() {
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        activePrompt = nil
    }

    // MARK: Événements

    private func screenUnlocked() {
        guard animateUnlock else { return }
        context.presentAlert(UnlockAnimations.unlocked())
    }

    private func applicationAppeared(_ bundleID: String?) {
        guard let prompt = AuthPrompt(bundleIdentifier: bundleID), activePrompt?.kind != prompt else { return }
        switch prompt {
        case .touchID where animateTouchID: showPrompt(.touchID)
        case .password where animatePassword: showPrompt(.password)
        default: break
        }
    }

    private func applicationDisappeared(_ bundleID: String?) {
        guard let prompt = AuthPrompt(bundleIdentifier: bundleID), let active = activePrompt, active.kind == prompt else { return }
        // Petit délai : la fenêtre peut perdre le premier plan un instant pendant la saisie.
        let alertID = active.alertID
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, self.activePrompt?.alertID == alertID else { return }
            if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               AuthPrompt(bundleIdentifier: front) == prompt { return }
            self.activePrompt = nil
            self.context.dismiss(alertID)
        }
    }

    private func showPrompt(_ prompt: AuthPrompt) {
        let alert = prompt == .touchID ? UnlockAnimations.touchID() : UnlockAnimations.password()
        activePrompt = (prompt, alert.id)
        context.presentAlert(alert)
    }

    #if DEBUG
    /// Aperçu des animations (menu Débogage).
    func preview(_ kind: String) {
        switch kind {
        case "touchID": context.presentAlert(UnlockAnimations.touchID(duration: .seconds(4)))
        case "password": context.presentAlert(UnlockAnimations.password(duration: .seconds(4)))
        default: context.presentAlert(UnlockAnimations.unlocked())
        }
    }
    #endif

    // MARK: Affichage

    var compactPriority: ModulePriority { .none }

    var expandedWidthWeight: CGFloat { 1 }

    func expandedView() -> AnyView {
        AnyView(UnlockExpandedView(module: self))
    }

    func settingsView() -> AnyView? {
        AnyView(UnlockSettingsView(module: self))
    }
}
