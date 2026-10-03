import AppKit
import SwiftUI

/// Assemble les services de l'app et gère son cycle de vie.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    let entitlements = EntitlementManager()
    lazy var moduleManager = ModuleManager(settings: settings, entitlements: entitlements)
    lazy var viewModel = NotchViewModel(manager: moduleManager, settings: settings)

    private var notchWindow: NotchWindowController?
    private lazy var settingsWindow = SettingsWindowController { [unowned self] in
        AnyView(SettingsView(settings: settings, manager: moduleManager))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Les alertes des modules s'affichent dans l'encoche.
        moduleManager.alertHandler = { [weak self] alert in
            self?.viewModel.present(alert)
        }
        viewModel.openSettingsAction = { [weak self] in
            self?.showSettings()
        }

        moduleManager.reload()

        let controller = NotchWindowController(viewModel: viewModel, settings: settings)
        controller.show()
        notchWindow = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        moduleManager.stopAll()
    }

    // MARK: - Actions du menu

    func showSettings() {
        settingsWindow.show()
    }

    /// Affiche une alerte factice pour vérifier le système d'alertes.
    func presentTestAlert() {
        viewModel.present(NotchAlert(
            leading: AnyView(Image(systemName: "bell.fill").foregroundStyle(.yellow)),
            trailing: AnyView(Text("Test")),
            duration: .seconds(3)
        ))
    }
}
