import Foundation
import SwiftUI
import Testing
@testable import Notchkit

// MARK: - Modules factices

@MainActor
@Observable
final class MockModuleA: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "mock.a", name: "A", summary: "", systemImage: "a.circle",
        category: .widgets, tier: .free, defaultEnabled: true
    )
    var startCount = 0
    var stopCount = 0
    var compactPriority: ModulePriority = .low

    init(context: ModuleContext) {}
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

@MainActor
@Observable
final class MockModuleB: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "mock.b", name: "B", summary: "", systemImage: "b.circle",
        category: .media, tier: .pro, defaultEnabled: false
    )
    var compactPriority: ModulePriority = .low

    init(context: ModuleContext) {}
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

// MARK: - Tests

@MainActor
struct ModuleManagerTests {
    let settings = SettingsStore(defaults: UserDefaults(suiteName: "notchkit.tests.\(UUID().uuidString)")!)

    func makeManager() -> ModuleManager {
        ModuleManager(
            settings: settings,
            entitlements: EntitlementManager(),
            availableModules: [MockModuleA.self, MockModuleB.self]
        )
    }

    @Test func chargeUniquementLesModulesActivesParDefaut() {
        let manager = makeManager()
        manager.reload()
        #expect(manager.activeModules.map(\.moduleID) == ["mock.a"])
        #expect((manager.module(for: "mock.a") as? MockModuleA)?.startCount == 1)
    }

    @Test func activerPuisDesactiverDemarreEtArrete() throws {
        let manager = makeManager()
        manager.reload()
        let a = try #require(manager.module(for: "mock.a") as? MockModuleA)

        manager.setEnabled(true, for: "mock.b")
        #expect(manager.activeModules.count == 2)
        #expect(a.startCount == 1, "un module déjà chargé ne doit pas redémarrer")

        manager.setEnabled(false, for: "mock.a")
        #expect(a.stopCount == 1)
        #expect(manager.module(for: "mock.a") == nil)
        #expect(settings.settings.moduleEnabled["mock.a"] == false)
    }

    @Test func moduleCompactSelonPrioriteEtOrdre() throws {
        let manager = makeManager()
        manager.setEnabled(true, for: "mock.b")
        let a = try #require(manager.module(for: "mock.a") as? MockModuleA)
        let b = try #require(manager.module(for: "mock.b") as? MockModuleB)

        // Égalité : l'ordre de l'utilisateur l'emporte.
        #expect(manager.compactModule?.moduleID == "mock.a")
        settings.settings.moduleOrder = ["mock.b", "mock.a"]
        manager.reload()
        #expect(manager.compactModule?.moduleID == "mock.b")

        // Priorité plus haute : elle l'emporte sur l'ordre.
        a.compactPriority = .high
        #expect(manager.compactModule?.moduleID == "mock.a")

        // Aucun module ne demande d'affichage.
        a.compactPriority = .none
        b.compactPriority = .none
        #expect(manager.compactModule == nil)
    }
}

struct AppSettingsTests {
    @Test func decodageToleranteAuxClesManquantes() throws {
        let json = Data(#"{"simulateNotch": true}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
        #expect(decoded.simulateNotch)
        #expect(decoded.screenSelection == .primary)
        #expect(decoded.hoverCloseDelay == AppSettings().hoverCloseDelay)
    }

    @Test func allerRetourJSON() throws {
        var settings = AppSettings()
        settings.screenSelection = .specific(id: "ABC", name: "Studio Display")
        settings.moduleEnabled = ["clock": false]
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
    }

    @Test func selectionEcranComparéeParIdentifiant() {
        #expect(ScreenSelection.specific(id: "X", name: "Ancien nom") == .specific(id: "X", name: "Nouveau nom"))
        #expect(ScreenSelection.specific(id: "X", name: "A") != .specific(id: "Y", name: "A"))
    }
}

struct NotchLayoutTests {
    let notch = NotchGeometry(
        style: .notch, closedSize: CGSize(width: 185, height: 32),
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), centerX: 756
    )
    let pill = NotchGeometry(
        style: .pill, closedSize: CGSize(width: 96, height: 20),
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), centerX: 720
    )

    @Test func encocheRepliéeEpouseLEncochePhysique() {
        let size = NotchLayout.shapeSize(for: notch, isExpanded: false, hasCompactContent: false)
        #expect(size == CGSize(width: 185 + NotchLayout.earRadius * 2, height: 32))
    }

    @Test func contenuCompactElargitDeChaqueCote() {
        let size = NotchLayout.shapeSize(for: notch, isExpanded: false, hasCompactContent: true)
        #expect(size.width == 185 + NotchLayout.compactSideWidth * 2 + NotchLayout.earRadius * 2)
    }

    @Test func pastilleAvecDecalageEnHaut() {
        let shape = NotchLayout.shapeSize(for: pill, isExpanded: true, hasCompactContent: false)
        let panel = NotchLayout.panelSize(for: pill, isExpanded: true, hasCompactContent: false)
        #expect(panel.height == shape.height + NotchLayout.pillTopInset)
        #expect(shape.width == NotchLayout.expandedSize.width)
    }
}
