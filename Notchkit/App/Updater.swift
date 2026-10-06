import AppKit
import Sparkle

/// Mises à jour automatiques avec Sparkle (licence MIT).
///
/// Notchkit lit la liste des versions (`appcast.xml`, à la racine du dépôt GitHub), télécharge le
/// `.dmg` de la nouvelle version, vérifie sa signature EdDSA (clé publique `SUPublicEDKey` dans
/// l'Info.plist, clé privée dans le trousseau du développeur), remplace l'app puis la relance.
///
/// Désactivé dans les versions de développement et les lancements automatisés : une version Debug
/// ne doit pas se remplacer par la version publiée.
@MainActor
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController?

    /// Mises à jour possibles (version publiée, hors tests).
    var isAvailable: Bool { controller != nil }

    func start() {
        #if DEBUG
        return
        #else
        guard controller == nil, !AutomatedRun.isActive else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
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
