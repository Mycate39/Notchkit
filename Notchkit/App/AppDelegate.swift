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
    private let settingsRouter = SettingsRouter()
    private lazy var settingsWindow = SettingsWindowController { [unowned self] in
        AnyView(SettingsView(settings: settings, manager: moduleManager, router: settingsRouter))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Les alertes des modules s'affichent dans l'encoche.
        moduleManager.alertHandler = { [weak self] alert in
            self?.viewModel.present(alert)
        }
        viewModel.openSettingsAction = { [weak self] tab in
            self?.showSettings(tab: tab)
        }
        moduleManager.settingsHandler = { [weak self] in
            self?.viewModel.openSettings()
        }
        moduleManager.holdHandler = { [weak self] hold in
            self?.viewModel.setHold(hold)
        }
        moduleManager.dismissAlertHandler = { [weak self] id in
            self?.viewModel.dismissAlert(id: id)
        }
        moduleManager.blockExpansionHandler = { [weak self] blocked in
            self?.viewModel.setExpansionBlocked(blocked)
        }
        // Fichiers glissés sur l'encoche : étagère ou AirDrop.
        viewModel.dropHandlerAvailability = { [weak self] in
            self?.moduleManager.module(for: ShelfModule.descriptor.id) != nil
        }
        viewModel.dropHandler = { [weak self] urls, zone in
            guard let self else { return }
            switch zone {
            case .shelf:
                if let shelf = self.moduleManager.module(for: ShelfModule.descriptor.id) as? ShelfModule {
                    let added = shelf.add(urls)
                    if added > 0 { self.viewModel.present(ShelfAlerts.added(added)) }
                }
            case .airDrop:
                AirDrop.send(urls)
            }
        }

        moduleManager.reload()

        let controller = NotchWindowController(viewModel: viewModel, settings: settings)
        controller.show()
        notchWindow = controller

        #if DEBUG
        if ProcessInfo.processInfo.environment["NOTCHKIT_STRESS"] != nil {
            runStressTest()
        }
        if let directory = ProcessInfo.processInfo.environment["NOTCHKIT_SNAPSHOT"] {
            Task { @MainActor in
                // Laisse le temps aux modules de charger leurs données (météo, calendrier…).
                try? await Task.sleep(for: .seconds(4))
                SnapshotRenderer.renderAll(to: URL(fileURLWithPath: directory), viewModel: viewModel,
                                           settings: settings, manager: moduleManager)
                NSApp.terminate(nil)
            }
        }
        #endif
    }

    #if DEBUG
    /// Aperçu des animations de déverrouillage (le module doit être activé).
    func previewUnlock(_ kind: String) {
        (moduleManager.module(for: UnlockModule.descriptor.id) as? UnlockModule)?.preview(kind)
    }

    /// Simule un événement de batterie (le module doit être activé).
    func simulateBattery(_ event: BatteryEvent) {
        (moduleManager.module(for: BatteryModule.descriptor.id) as? BatteryModule)?.simulate(event)
    }

    /// Test de charge : déplie/replie l'encoche 200 fois à intervalles aléatoires, avec des alertes
    /// des changements de page et de fenêtre active. Lancer l'app avec la variable d'environnement
    /// `NOTCHKIT_STRESS=1` ; « STRESS-OK » s'affiche dans la console à la fin si tout s'est bien passé.
    private func runStressTest() {
        Task { @MainActor in
            for i in 0..<200 {
                try? await Task.sleep(for: .milliseconds(Int.random(in: 150...900)))
                viewModel.toggle()
                if i % 7 == 0 { presentTestAlert() }
                if i % 3 == 0 { viewModel.selectedPage = Int.random(in: 0...1) }
                if let panel = NSApp.windows.first(where: { $0 is NotchPanel }) {
                    if i.isMultiple(of: 2) { panel.makeKey() } else { panel.resignKey() }
                }
                FileHandle.standardError.write(Data("stress \(i)\n".utf8))
            }
            FileHandle.standardError.write(Data("STRESS-OK\n".utf8))
        }
    }
    #endif

    /// Liens `notchkit://…` (activités live : progression de tâches, minuteurs).
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let activities = moduleManager.module(for: LiveActivitiesModule.descriptor.id) as? LiveActivitiesModule else { return }
        for url in urls {
            if let command = LiveActivityCommand(url: url) { activities.handle(command) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        moduleManager.stopAll()
    }

    // MARK: - Actions du menu

    func showSettings(tab: SettingsTab? = nil) {
        if let tab { settingsRouter.tab = tab }
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
