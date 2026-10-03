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

        #if DEBUG
        if ProcessInfo.processInfo.environment["NOTCHKIT_STRESS"] != nil {
            runStressTest()
        }
        #endif
    }

    #if DEBUG
    /// Simule un événement de batterie (le module doit être activé).
    func simulateBattery(_ event: BatteryEvent) {
        (moduleManager.module(for: BatteryModule.descriptor.id) as? BatteryModule)?.simulate(event)
    }

    /// Test de charge : déplie/replie l'encoche 200 fois à intervalles aléatoires, avec des alertes
    /// et des changements de fenêtre active. Lancer l'app avec la variable d'environnement
    /// `NOTCHKIT_STRESS=1` ; « STRESS-OK » s'affiche dans la console à la fin si tout s'est bien passé.
    private func runStressTest() {
        Task { @MainActor in
            for i in 0..<200 {
                try? await Task.sleep(for: .milliseconds(Int.random(in: 150...900)))
                viewModel.toggle()
                if i % 7 == 0 { presentTestAlert() }
                if let panel = NSApp.windows.first(where: { $0 is NotchPanel }) {
                    if i.isMultiple(of: 2) { panel.makeKey() } else { panel.resignKey() }
                }
                FileHandle.standardError.write(Data("stress \(i)\n".utf8))
            }
            FileHandle.standardError.write(Data("STRESS-OK\n".utf8))
        }
    }
    #endif

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
