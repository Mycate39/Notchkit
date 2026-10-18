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
