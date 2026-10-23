import Foundation
import SwiftUI
import Testing
@testable import Notchkit

@MainActor
@Observable
final class MockLockScreenModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "mock.lockscreen", name: "L", summary: "", systemImage: "l.circle",
        category: .media, tier: .free, defaultEnabled: true
    )
    var compactPriority: ModulePriority { .high }
    init(context: ModuleContext) {}
    func compactLeading() -> AnyView? { AnyView(Text(verbatim: "L")) }
    func lockScreenLeading() -> AnyView? { AnyView(Text(verbatim: "Titre")) }
    func lockScreenTrailing() -> AnyView? { AnyView(Text(verbatim: "▶︎")) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

/// Lecteur en pause : pas d'activité principale, mais une bulle (comme la musique).
@MainActor
@Observable
final class MockPausedPlayerModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "mock.paused", name: "M", summary: "", systemImage: "m.circle",
        category: .media, tier: .free, defaultEnabled: true
    )
    var compactPriority: ModulePriority { .none }
    var bubblePriority: ModulePriority { .normal }
    init(context: ModuleContext) {}
    func compactLeading() -> AnyView? { AnyView(Text(verbatim: "M")) }
    func lockScreenLeading() -> AnyView? { AnyView(Text(verbatim: "Titre")) }
    func lockScreenTrailing() -> AnyView? { AnyView(Text(verbatim: "▶︎")) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

/// Lecteur de l'écran verrouillé : l'activité s'élargit et devient cliquable, seulement verrouillé.
@MainActor
struct LockScreenPlayerTests {
    private func makeViewModel(_ modules: [any NotchModule.Type]) -> NotchViewModel {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "notchkit.tests.\(UUID().uuidString)")!)
        let manager = ModuleManager(settings: settings, entitlements: EntitlementManager(), availableModules: modules)
        manager.reload()
        return NotchViewModel(manager: manager, settings: settings)
    }

    @Test func lecteurSeulementQuandLeMacEstVerrouille() {
        let viewModel = makeViewModel([MockLockScreenModule.self])
        #expect(viewModel.lockScreenModule == nil)
        #expect(viewModel.compactSideWidth == NotchLayout.activitySideWidth)

        viewModel.setScreenLocked(true)
        #expect(viewModel.lockScreenModule?.moduleID == "mock.lockscreen")
        #expect(viewModel.compactSideWidth == NotchLayout.lockScreenSideWidth)

        viewModel.setScreenLocked(false)
        #expect(viewModel.lockScreenModule == nil)
    }

    @Test func lecteurGardeEnPause() {
        let viewModel = makeViewModel([MockPausedPlayerModule.self])
        // En pause, seul : l'encoche est vide.
        #expect(viewModel.manager.compactModule == nil)
        #expect(!viewModel.hasCompactContent)

        viewModel.setScreenLocked(true)
        #expect(viewModel.lockScreenModule?.moduleID == "mock.paused")
        #expect(viewModel.hasCompactContent)
        viewModel.setScreenLocked(false)
    }

    @Test func autreActivitePrincipaleGardeSaPlace() {
        let viewModel = makeViewModel([MockPrimaryModule.self, MockPausedPlayerModule.self])
        viewModel.setScreenLocked(true)
        #expect(viewModel.manager.compactModule?.moduleID == "mock.primary")
        #expect(viewModel.lockScreenModule == nil)
        viewModel.setScreenLocked(false)
    }

    @Test func activiteSansLecteurResteInerte() {
        let viewModel = makeViewModel([MockPrimaryModule.self])
        viewModel.setScreenLocked(true)
        #expect(viewModel.lockScreenModule == nil)
        #expect(viewModel.compactSideWidth == NotchLayout.activitySideWidth)
    }
}
