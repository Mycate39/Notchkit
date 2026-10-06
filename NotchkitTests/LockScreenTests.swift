import Foundation
import Testing
@testable import Notchkit

/// Écran verrouillé : l'encoche reste affichée repliée, mais rien ne se déplie.
@MainActor
struct LockScreenTests {
    private func makeViewModel() -> NotchViewModel {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "notchkit.tests.\(UUID().uuidString)")!)
        let manager = ModuleManager(settings: settings, entitlements: EntitlementManager(),
                                    availableModules: [MockModuleA.self])
        return NotchViewModel(manager: manager, settings: settings)
    }

    @Test func verrouillageReplieEtBloqueLOuverture() {
        let viewModel = makeViewModel()
        viewModel.expand()
        #expect(viewModel.isExpanded)
        // Verrouillage : l'encoche se replie et ne peut plus s'ouvrir.
        viewModel.setScreenLocked(true)
        #expect(!viewModel.isExpanded)
        viewModel.expand()
        viewModel.toggle()
        #expect(!viewModel.isExpanded)
        // Déverrouillage : elle s'ouvre de nouveau.
        viewModel.setScreenLocked(false)
        viewModel.expand()
        #expect(viewModel.isExpanded)
    }
}
