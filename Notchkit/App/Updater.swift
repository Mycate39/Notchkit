import AppKit
import Sparkle

/// Mises à jour automatiques avec Sparkle (licence MIT).
///
/// Notchkit lit la liste des versions (`appcast.xml`, à la racine du dépôt GitHub), télécharge le
/// `.dmg` de la nouvelle version, vérifie sa signature EdDSA (clé publique `SUPublicEDKey` dans
/// l'Info.plist, clé privée dans le trousseau du développeur), remplace l'app puis la relance.
///
/// Versions bêta : les entrées de l'appcast marquées `<sparkle:channel>beta</sparkle:channel>` ne
/// sont proposées qu'aux personnes qui ont activé « Recevoir les versions bêta » (activé d'office
/// quand la version installée est elle-même une bêta ou une RC). Les autres ne voient que les
/// versions finales.
///
/// Désactivé dans les versions de développement et les lancements automatisés : une version Debug
/// ne doit pas se remplacer par la version publiée.
@MainActor
final class Updater: NSObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController?

    /// Mises à jour possibles (version publiée, hors tests).
    var isAvailable: Bool { controller != nil }

    func start() {
        #if DEBUG
        return
        #else
        guard controller == nil, !AutomatedRun.isActive else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        #endif
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Recherche automatique (une fois par jour), réglable dans Réglages > Général.
    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    // MARK: Versions bêta

    nonisolated static let betaChannel = "beta"
    nonisolated static let receivesBetasKey = "updates.receiveBetas"

    /// Version installée : bêta ou candidate (« 3.0.0-beta.4 », « 3.0.0-rc.1 »).
    nonisolated static func isPrerelease(_ version: String) -> Bool {
        version.contains("-beta") || version.contains("-rc")
    }

    /// Réglage choisi, sinon activé si la version installée est une bêta.
    nonisolated static func receivesBetas(stored: Bool?, installedVersion: String) -> Bool {
        stored ?? isPrerelease(installedVersion)
    }

    /// Recevoir les versions bêta (Réglages > Général > Mises à jour).
    var receivesBetas: Bool {
        get { Self.receivesBetas(stored: UserDefaults.standard.object(forKey: Self.receivesBetasKey) as? Bool,
                                 installedVersion: Self.installedVersion) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.receivesBetasKey)
            // Nouvelle recherche au prochain cycle, avec le canal à jour.
            controller?.updater.resetUpdateCycleAfterShortDelay()
        }
    }

    nonisolated private static var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        let stored = UserDefaults.standard.object(forKey: Self.receivesBetasKey) as? Bool
        return Self.receivesBetas(stored: stored, installedVersion: Self.installedVersion) ? [Self.betaChannel] : []
    }

    // MARK: SPUStandardUserDriverDelegate

    // App d'arrière-plan (pas d'icône dans le Dock) : Sparkle doit savoir qu'il peut afficher
    // ses rappels sans que l'app soit au premier plan.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                               forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        // La fenêtre de mise à jour passe devant les autres apps.
        Task { @MainActor in NSApp.activate(ignoringOtherApps: true) }
    }
}
