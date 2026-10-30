import AppKit
import SwiftUI

/// Assemble les services de l'app et gère son cycle de vie.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore(defaults: AutomatedRun.settingsDefaults)
    let entitlements = EntitlementManager()
    lazy var moduleManager = ModuleManager(settings: settings, entitlements: entitlements)
    lazy var viewModel = NotchViewModel(manager: moduleManager, settings: settings)

    private var notchWindow: NotchWindowController?
    private var sigtermSource: DispatchSourceSignal?
    private let settingsRouter = SettingsRouter()
    private lazy var settingsWindow = SettingsWindowController { [unowned self] in
        AnyView(SettingsView(settings: settings, manager: moduleManager, router: settingsRouter))
    }
    private lazy var onboardingWindow = OnboardingWindowController(
        settings: settings, manager: moduleManager, viewModel: viewModel,
        openSettings: { [unowned self] tab in self.showSettings(tab: tab) }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `kill` (SIGTERM) passe par une fermeture normale : les modules arrêtent leurs processus.
        signal(SIGTERM, SIG_IGN)
        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        sigterm.resume()
        sigtermSource = sigterm

        // Mises à jour automatiques (versions publiées uniquement).
        Updater.shared.start()

        // Les alertes des modules s'affichent dans l'encoche.
        moduleManager.alertHandler = { [weak self] alert in
            self?.viewModel.present(alert)
        }
        viewModel.openSettingsAction = { [weak self] tab in
            self?.showSettings(tab: tab)
        }
        // « Configurer… » depuis un widget : ouvre directement la page du module.
        moduleManager.settingsHandler = { [weak self] moduleID in
            self?.viewModel.openSettings(tab: moduleID.map(SettingsTab.module))
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
        moduleManager.showModuleHandler = { [weak self] moduleID in
            self?.viewModel.expand(showing: moduleID)
        }
        moduleManager.quietHandler = { [weak self] quiet in
            self?.viewModel.setQuiet(quiet)
        }
        // Fichiers glissés sur l'encoche : étagère ou AirDrop.
        // L'étagère accepte toujours les fichiers, même si son widget est masqué (elle s'affiche alors
        // en dernière page tant qu'elle n'est pas vide).
        // Étagère, conversion et AirDrop sont toujours proposés : l'étagère et le convertisseur sont
        // des widgets temporaires, qui s'affichent même masqués tant qu'ils ont du contenu.
        viewModel.dropZonesProvider = { [weak self] in
            guard let self else { return [.airDrop] }
            var zones: [DropZone] = []
            if self.moduleManager.isUnlocked(ShelfModule.descriptor) { zones.append(.shelf) }
            if self.moduleManager.module(for: ConverterModule.descriptor.id) != nil { zones.append(.convert) }
            zones.append(.airDrop)
            return zones
        }
        // Fichier glissé au-dessus du convertisseur ouvert : déposé directement dedans.
        viewModel.directDropModules = [ConverterModule.descriptor.id]
        viewModel.directDropChanged = { [weak self] old, new in
            guard let self else { return }
            for id in [old, new].compactMap({ $0 }) {
                (self.moduleManager.module(for: id) as? ConverterModule)?.isDropTargeted = (id == new)
            }
        }
        viewModel.directDropHandler = { [weak self] urls, id in
            (self?.moduleManager.module(for: id) as? ConverterModule)?.add(urls)
        }
        viewModel.dropHandler = { [weak self] urls, zone in
            guard let self else { return }
            switch zone {
            case .shelf:
                // L'étagère tourne toujours (module contextuel), même si son widget est masqué.
                if let shelf = self.moduleManager.module(for: ShelfModule.descriptor.id) as? ShelfModule {
                    let added = shelf.add(urls)
                    if added > 0 { self.viewModel.present(ShelfAlerts.added(added)) }
                }
            case .convert:
                guard let converter = self.moduleManager.module(for: ConverterModule.descriptor.id) as? ConverterModule else { break }
                if converter.add(urls) > 0 {
                    // L'encoche se replie après le dépôt : on la rouvre sur le convertisseur pour choisir le format.
                    DispatchQueue.main.async { self.viewModel.expand(showing: ConverterModule.descriptor.id) }
                } else if !converter.isConverting {
                    // Aucun format possible (archive, dossier…) : on le dit au lieu de ne rien faire.
                    self.viewModel.present(ConverterAlerts.unsupported())
                }
            case .airDrop:
                AirDrop.send(urls)
            }
        }

        moduleManager.reload()

        // Apparence et retour haptique : appliqués au lancement puis à chaque modification des réglages.
        viewModel.applyAppearance(settings.settings.appearance)
        Haptics.isEnabled = settings.settings.hapticsEnabled
        applyMascotSounds()
        trackChanges(of: { [weak self] in
            _ = self?.settings.settings.appearance
            _ = self?.settings.settings.hapticsEnabled
            _ = self?.settings.settings.mascotSounds
            _ = self?.settings.settings.mascotSoundVolume
        }, perform: { [weak self] in
            guard let self else { return }
            self.viewModel.applyAppearance(self.settings.settings.appearance)
            Haptics.isEnabled = self.settings.settings.hapticsEnabled
            self.applyMascotSounds()
        })

        let controller = NotchWindowController(viewModel: viewModel, settings: settings)
        controller.show()
        notchWindow = controller

        // Première installation : tutoriel de bienvenue, une fois l'encoche en place.
        if !settings.settings.onboardingCompleted && !AutomatedRun.isActive {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                self.showOnboarding()
            }
        }

        #if DEBUG
        if ProcessInfo.processInfo.environment["NOTCHKIT_STRESS"] != nil {
            runStressTest()
        }
        if let directory = ProcessInfo.processInfo.environment["NOTCHKIT_MASCOT_VIDEO"] {
            // Images de la vidéo de démonstration de la mascotte (celle choisie dans les réglages).
            Task { @MainActor in
                MascotVideoRenderer.renderFrames(design: settings.settings.mascot,
                                                 to: URL(fileURLWithPath: directory))
                NSApp.terminate(nil)
            }
        }
        if let scenario = ProcessInfo.processInfo.environment["NOTCHKIT_DEMO"] {
            // Tournage : joue le scénario sur la vraie encoche et l'enregistre (voir `DemoDirector`).
            let output = ProcessInfo.processInfo.environment["NOTCHKIT_DEMO_OUTPUT"]
                ?? URL(fileURLWithPath: scenario).deletingLastPathComponent().path
            Task { @MainActor in
                // Laisse l'encoche se placer et les modules démarrer.
                try? await Task.sleep(for: .seconds(2))
                await DemoDirector(scenarioURL: URL(fileURLWithPath: scenario), outputURL: URL(fileURLWithPath: output),
                                   viewModel: viewModel, manager: moduleManager, window: controller,
                                   settings: settings).run()
                DemoSettings.discard()
                NSApp.terminate(nil)
            }
        }
        if let directory = ProcessInfo.processInfo.environment["NOTCHKIT_SNAPSHOT"] {
            Task { @MainActor in
                // Laisse le temps aux modules de charger leurs données (météo, calendrier…).
                try? await Task.sleep(for: .seconds(4))
                SnapshotRenderer.renderAll(to: URL(fileURLWithPath: directory), viewModel: viewModel,
                                           settings: settings, manager: moduleManager)
                PromoSnapshots.renderAll(to: URL(fileURLWithPath: directory))
                try? self.notchWindow?.diagnosticReport()
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("diagnostic.txt"), atomically: true, encoding: .utf8)
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

    /// App relancée depuis le Finder alors qu'elle tourne déjà : on ouvre les réglages (seul moyen
    /// d'y revenir quand l'icône de la barre des menus est masquée, avec la roue dentée de l'encoche).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Tests et captures : jamais de fenêtre (le lanceur des tests attendrait indéfiniment).
        guard !AutomatedRun.isActive else { return false }
        showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        moduleManager.stopAll()
    }

    // MARK: - Actions du menu

    /// Copie le rapport de diagnostic (écrans, encoche, fenêtre) pour signaler un problème.
    func copyDiagnostics() {
        guard let report = notchWindow?.diagnosticReport() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    func showOnboarding() {
        onboardingWindow.show()
    }

    private func applyMascotSounds() {
        MascotSounds.isEnabled = settings.settings.mascotSounds
        MascotSounds.volume = Float(settings.settings.mascotSoundVolume)
    }

    func showSettings(tab: SettingsTab? = nil) {
        if let tab { settingsRouter.tab = tab }
        settingsWindow.show(title: settingsRouter.tab.title(in: moduleManager))
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
