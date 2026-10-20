import CoreAudio
import Foundation
import Testing
@testable import Notchkit

/// Mode jeu : reconnaissance des jeux et encoche discrète.
@MainActor
struct GameModeTests {
    @Test func jeuxReconnus() {
        #expect(GameDetector.isGame(category: "public.app-category.games", path: nil))
        #expect(GameDetector.isGame(category: "public.app-category.action-games", path: nil))
        #expect(GameDetector.isGame(category: nil, path: "/Users/moi/Library/Application Support/Steam/steamapps/common/Hades/Hades.app"))
        #expect(!GameDetector.isGame(category: "public.app-category.productivity", path: "/Applications/Notes.app"))
        #expect(!GameDetector.isGame(category: nil, path: nil))
        #expect(GameDetector.isGame(category: nil, path: "/Applications/Jeu.app", supportsGameMode: true))
    }

    @Test func pleinEcranCommeLeModeJeuDeMacOS() {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let second = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        // Plein écran, y compris sous l'encoche pour une app qui ne l'utilise pas.
        #expect(FullScreenDetector.isFullScreen(windows: [display], displays: [display, second]))
        #expect(FullScreenDetector.isFullScreen(windows: [CGRect(x: 0, y: 32, width: 1512, height: 950)], displays: [display]))
        #expect(FullScreenDetector.isFullScreen(windows: [second], displays: [display, second]))
        // Fenêtre simplement agrandie (sous la barre des menus et au-dessus du Dock), ou plus petite.
        #expect(!FullScreenDetector.isFullScreen(windows: [CGRect(x: 0, y: 33, width: 1512, height: 870)], displays: [display]))
        #expect(!FullScreenDetector.isFullScreen(windows: [CGRect(x: 100, y: 100, width: 800, height: 600)], displays: [display]))
        #expect(!FullScreenDetector.isFullScreen(windows: [], displays: [display]))
    }

    @Test func imagesParSecondeSurLaDerniereSeconde() {
        let frames = (0..<180).map { 10 + Double($0) / 60 }  // 3 s à 60 images par seconde
        #expect(FrameRateMeter.fps(frameTimes: frames, now: 12.99) == 60)
        #expect(FrameRateMeter.fps(frameTimes: frames, now: 20) == 0)
        #expect(FrameRateMeter.fps(frameTimes: [], now: 1) == 0)
    }

    @Test func activationAutomatiqueOuManuelle() {
        #expect(GameModeModule.shouldBeActive(manual: nil, automatic: true, gameInFront: true))
        #expect(!GameModeModule.shouldBeActive(manual: nil, automatic: false, gameInFront: true))
        #expect(GameModeModule.shouldBeActive(manual: true, automatic: false, gameInFront: false))
        #expect(!GameModeModule.shouldBeActive(manual: false, automatic: true, gameInFront: true))
    }

    @Test func encocheDiscretePendantLaPartie() {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "notchkit.tests.\(UUID().uuidString)")!)
        let manager = ModuleManager(settings: settings, entitlements: EntitlementManager(), availableModules: [MockModuleA.self])
        let viewModel = NotchViewModel(manager: manager, settings: settings)
        viewModel.setQuiet(true)
        // Ni gonflement au survol, ni ouverture sur un module, ni alerte.
        viewModel.hoverChanged(isInside: true)
        #expect(!viewModel.showsHoverShadow)
        viewModel.expand(showing: "a")
        #expect(!viewModel.isExpanded)
        viewModel.present(NotchAlert(duration: .seconds(1)))
        #expect(viewModel.currentAlert == nil)
        // Fin de partie : tout redevient normal.
        viewModel.setQuiet(false)
        viewModel.hoverChanged(isInside: true)
        #expect(viewModel.showsHoverShadow)
        viewModel.hoverChanged(isInside: false)
    }
}

/// Centre du son : rattachement des processus auxiliaires et types d'appareils.
struct AudioCenterTests {
    @Test func processusAuxiliaireRattacheASonApp() {
        #expect(AudioCenter.outermostApp(in: "/Applications/Discord.app/Contents/Frameworks/Discord Helper (Renderer).app/Contents/MacOS/Discord Helper (Renderer)")
                == "/Applications/Discord.app")
        #expect(AudioCenter.outermostApp(in: "/usr/libexec/coreaudiod") == nil)
    }

    @Test func appsQuiJouentRegroupentTousLeursProcessus() {
        // Brave (10) joue par un auxiliaire ; Discord (20) ne joue pas ; Musique (30) est « À l'écoute » sans sortie signalée.
        let entries: [(object: AudioObjectID, owner: pid_t, output: Bool)] = [
            (5, 10, false), (6, 10, true), (7, 20, false), (8, 30, false), (4, 10, false),
        ]
        let groups = AudioCenter.playingGroups(entries, nowPlaying: 30)
        #expect(groups == [10: [4, 5, 6], 30: [8]])
        #expect(AudioCenter.playingGroups(entries, nowPlaying: nil) == [10: [4, 5, 6]])
    }

    @Test func typesDAppareils() {
        #expect(AudioDevice.kind(transport: kAudioDeviceTransportTypeBuiltIn) == .builtIn)
        #expect(AudioDevice.kind(transport: kAudioDeviceTransportTypeBluetooth) == .bluetooth)
        #expect(AudioDevice(id: 1, name: "AirPods Pro de Léa", kind: .bluetooth, hasOutput: true, hasInput: true).symbol == "airpodspro")
        #expect(AudioDevice(id: 2, name: "Haut-parleurs MacBook Pro", kind: .builtIn, hasOutput: true, hasInput: false).symbol == "laptopcomputer")
    }
}
