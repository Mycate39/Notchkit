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

@MainActor
@Observable
final class MockContextualModule: NotchModule {
    static let descriptor = ModuleDescriptor(
        id: "mock.contextual", name: "C", summary: "", systemImage: "c.circle",
        category: .widgets, tier: .free, defaultEnabled: false
    )
    /// Contenu simulé (statique, comme les fichiers enregistrés de l'étagère).
    nonisolated(unsafe) static var hasContent = false
    static var hasContextualContent: Bool { hasContent }
    var compactPriority: ModulePriority = .none

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

    @Test func decalagePourLibererLesMenus() {
        // Menus jusqu'à 672 pt, encoche centrée à 840 pt de 330 pt de large : bord gauche à 675,
        // décalée jusqu'à 672 + marge.
        #expect(MenuBarAvoidance.offset(menusRightEdge: 672, centerX: 840, halfWidth: 165) == 672 + MenuBarAvoidance.margin - 675)
        // Menus courts : pas de décalage.
        #expect(MenuBarAvoidance.offset(menusRightEdge: 400, centerX: 840, halfWidth: 165) == 0)
        // Autorisation absente ou menus illisibles : pas de décalage.
        #expect(MenuBarAvoidance.offset(menusRightEdge: nil, centerX: 840, halfWidth: 165) == 0)
        // Décalage plafonné.
        #expect(MenuBarAvoidance.offset(menusRightEdge: 1600, centerX: 840, halfWidth: 165) == MenuBarAvoidance.maxOffset)
    }

    @Test func largeurDesBulles() {
        let d = NotchLayout.bubbleDiameter(for: pill)
        #expect(NotchLayout.bubblesWidth(count: 0, geometry: pill) == 0)
        #expect(NotchLayout.bubblesWidth(count: 1, geometry: pill) == d + NotchLayout.bubbleGap)
        // À partir de deux activités, une seule place : la pile qui se déroule au survol.
        #expect(NotchLayout.bubblesWidth(count: 3, geometry: pill) == d + NotchLayout.bubbleGap)
        // Menu déroulé : bulles empilées, au plus `maxBubbles`.
        #expect(NotchLayout.bubbleMenuHeight(count: 2, geometry: pill) == 2 * d + NotchLayout.bubbleGap)
        #expect(NotchLayout.bubbleMenuHeight(count: 9, geometry: pill)
                == NotchLayout.bubbleMenuHeight(count: NotchLayout.maxBubbles, geometry: pill))
        // Île : les bulles prennent sa hauteur pour rester alignées.
        let islandShape = NotchLayout.shapeSize(for: pill, isExpanded: false, hasCompactContent: true, island: true)
        #expect(NotchLayout.bubbleDiameter(for: pill, island: true) == islandShape.height)
        #expect(NotchLayout.bubbleDiameter(for: notch, island: true) == NotchLayout.bubbleDiameter(for: notch))
        // Mode encoche : mini-encoche plus large que haute, congés compris ; pastille : bulle ronde.
        #expect(NotchLayout.bubbleWidth(for: pill) == d)
        #expect(NotchLayout.bubbleWidth(for: notch) > NotchLayout.bubbleDiameter(for: notch) + NotchLayout.earRadius * 2)
        #expect(NotchLayout.bubblesWidth(count: 1, geometry: notch) == NotchLayout.bubbleWidth(for: notch) + NotchLayout.bubbleGap)
    }

    @Test func bullesZoneSepareeDeLEncoche() {
        let shape = CGSize(width: 300, height: 32)
        // Sur la grande encoche, y compris au ras du bord.
        #expect(NotchLayout.isOverNotch(dx: 0, fromTop: 10, shapeSize: shape, style: .notch))
        #expect(NotchLayout.isOverNotch(dx: 150, fromTop: 10, shapeSize: shape, style: .notch))
        // Sur la mini-encoche à droite (au-delà de l'espacement) : zone à part.
        let bubbleX = shape.width / 2 + NotchLayout.bubbleGap + 10
        #expect(!NotchLayout.isOverNotch(dx: bubbleX, fromTop: 10, shapeSize: shape, style: .notch))
        // Sous l'encoche (menu des bulles déroulé) : zone à part.
        #expect(!NotchLayout.isOverNotch(dx: 0, fromTop: 80, shapeSize: shape, style: .notch))
    }

    @Test func ileSeulementPourLaPastille() {
        // En mode encoche, l'affichage façon île ne change pas la forme (contenu hors des arrondis).
        let normal = NotchLayout.shapeSize(for: notch, isExpanded: false, hasCompactContent: true)
        let island = NotchLayout.shapeSize(for: notch, isExpanded: false, hasCompactContent: true, island: true)
        #expect(island == normal)
        // Pastille : un peu plus haute, aux proportions de la Dynamic Island.
        let pillIsland = NotchLayout.shapeSize(for: pill, isExpanded: false, hasCompactContent: true, island: true)
        #expect(pillIsland.height == 20 + NotchLayout.islandExtraHeight)
        #expect(pillIsland.width == (pillIsland.height * NotchLayout.islandAspectRatio).rounded())
    }

    @Test func pastilleAvecDecalageEnHaut() {
        let shape = NotchLayout.shapeSize(for: pill, isExpanded: true, hasCompactContent: false)
        let panel = NotchLayout.panelSize(for: pill, isExpanded: true, hasCompactContent: false)
        #expect(panel.height == shape.height + NotchLayout.pillTopInset)
        #expect(shape.width == NotchLayout.expandedSize.width)
    }
}

@MainActor
@Suite(.serialized)
struct ContextualModuleTests {
    let settings = SettingsStore(defaults: UserDefaults(suiteName: "notchkit.tests.\(UUID().uuidString)")!)

    func makeManager() -> ModuleManager {
        ModuleManager(settings: settings, entitlements: EntitlementManager(),
                      availableModules: [MockModuleA.self, MockContextualModule.self])
    }

    @Test func widgetMasqueSansContenuNeTournePas() {
        MockContextualModule.hasContent = false
        let manager = makeManager()
        manager.reload()
        #expect(manager.module(for: "mock.contextual") == nil)
        #expect(manager.pageIDs == [["mock.a"]])
    }

    @Test func widgetMasqueAvecContenuEnDernierePage() {
        MockContextualModule.hasContent = true
        defer { MockContextualModule.hasContent = false }
        let manager = makeManager()
        manager.reload()
        #expect(manager.contextualIDs == ["mock.contextual"])
        #expect(manager.pageIDs == [["mock.a"], ["mock.contextual"]])
    }

    @Test func chargementPourUnDepotPuisRetraitQuandVide() {
        MockContextualModule.hasContent = false
        let manager = makeManager()
        manager.reload()
        #expect(manager.loadContextually("mock.contextual") != nil)
        manager.reload()
        #expect(manager.module(for: "mock.contextual") == nil)
    }

    @Test func moduleActiveResteDansLaDisposition() {
        MockContextualModule.hasContent = true
        defer { MockContextualModule.hasContent = false }
        let manager = makeManager()
        manager.setEnabled(true, for: "mock.contextual")
        #expect(manager.contextualIDs.isEmpty)
        #expect(manager.pageIDs.flatMap { $0 }.contains("mock.contextual"))
        #expect(manager.pageIDs.count == 1)
    }
}
