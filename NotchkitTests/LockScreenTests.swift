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

    @Test func verrouillageIgnoreSurvolBullesEtDepot() {
        let viewModel = makeViewModel()
        viewModel.setScreenLocked(true)
        // Ni gonflement au survol, ni ouverture programmée.
        viewModel.hoverChanged(isInside: true)
        #expect(!viewModel.showsHoverShadow)
        // Ni menu des bulles, ni mode dépôt de fichiers.
        viewModel.setBubbleMenuOpen(true)
        #expect(!viewModel.isBubbleMenuOpen)
        viewModel.fileDragMoved(normalizedX: 0.5)
        #expect(!viewModel.isDropMode)
        #expect(!viewModel.isExpanded)
        // Déverrouillage : le survol fonctionne de nouveau.
        viewModel.setScreenLocked(false)
        viewModel.hoverChanged(isInside: true)
        #expect(viewModel.showsHoverShadow)
        viewModel.hoverChanged(isInside: false)
    }
}
