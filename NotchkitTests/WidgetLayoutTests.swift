import Foundation
import Testing
@testable import Notchkit

struct WidgetLayoutEngineTests {
    let weights: [String: CGFloat] = ["music": 2, "clock": 1, "battery": 1, "calendar": 2, "weather": 1.5]
    let active = ["music", "clock", "battery", "calendar", "weather"]

    @Test func sansDispositionRepartitionAutomatique() {
        let pages = WidgetLayoutEngine.pages(activeIDs: active, weights: weights, layout: nil)
        #expect(pages == [["music", "clock", "battery"], ["calendar", "weather"]])
    }

    @Test func dispositionUtilisateurRespecteeEtNouveauxModulesAjoutes() {
        let layout = WidgetLayout(pages: [["weather", "clock"], ["music"]])
        let pages = WidgetLayoutEngine.pages(activeIDs: active, weights: weights, layout: layout)
        // Les modules non placés (battery, calendar) sont répartis à la fin.
        #expect(pages == [["weather", "clock"], ["music"], ["battery", "calendar"]])
    }

    @Test func modulesInactifsIgnores() {
        let layout = WidgetLayout(pages: [["weather", "claude"], ["music"]])
        let pages = WidgetLayoutEngine.pages(activeIDs: ["music", "weather"], weights: weights, layout: layout)
        #expect(pages == [["weather"], ["music"]])
    }

    @Test func deplacerDansLaMemePage() {
        let layout = WidgetLayout(pages: [["a", "b", "c"]])
        #expect(WidgetLayoutEngine.move("a", toPage: 0, index: 3, in: layout).pages == [["b", "c", "a"]])
        #expect(WidgetLayoutEngine.move("c", toPage: 0, index: 0, in: layout).pages == [["c", "a", "b"]])
        #expect(WidgetLayoutEngine.move("a", toPage: 0, index: 2, in: layout).pages == [["b", "a", "c"]])
    }

    @Test func deplacerVersUneAutrePageOuUneNouvelle() {
        let layout = WidgetLayout(pages: [["a", "b"], ["c"]])
        #expect(WidgetLayoutEngine.move("a", toPage: 1, index: 0, in: layout).pages == [["b"], ["a", "c"]])
        #expect(WidgetLayoutEngine.move("b", toPage: 5, index: 0, in: layout).pages == [["a"], ["c"], ["b"]])
        // La page vidée disparaît.
        #expect(WidgetLayoutEngine.move("c", toPage: 0, index: .max, in: layout).pages == [["a", "b", "c"]])
    }

    @Test func tailleParDefautLaPlusProche() {
        #expect(WidgetSize(weight: 2) == .large)
        #expect(WidgetSize(weight: 1.5) == .medium)
        #expect(WidgetSize(weight: 1) == .small)
        #expect(WidgetSize(weight: 1.2) == .small)
    }

    @Test func dispositionConserveeDansLesReglages() throws {
        var settings = AppSettings()
        settings.widgetLayout = WidgetLayout(pages: [["music"], ["clock"]], sizes: ["music": .small])
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.widgetLayout == settings.widgetLayout)
    }
}

@MainActor
struct ModuleManagerLayoutTests {
    let settings = SettingsStore(defaults: UserDefaults(suiteName: "notchkit.tests.\(UUID().uuidString)")!)

    func makeManager() -> ModuleManager {
        let manager = ModuleManager(settings: settings, entitlements: EntitlementManager(),
                                    availableModules: [MockModuleA.self, MockModuleB.self])
        manager.setEnabled(true, for: "mock.b")
        return manager
    }

    @Test func changerLaTailleEtDeplacer() {
        let manager = makeManager()
        #expect(manager.pageIDs == [["mock.a", "mock.b"]])

        manager.setSize(.large, for: "mock.a")
        #expect(manager.size(for: "mock.a") == .large)

        manager.move("mock.b", toPage: 1, index: 0)
        #expect(manager.pageIDs == [["mock.a"], ["mock.b"]])
        #expect(manager.position(of: "mock.b")?.page == 1)
    }

    @Test func masquerRetireDeLaDispositionEtReactiverReplace() {
        let manager = makeManager()
        manager.move("mock.b", toPage: 1, index: 0)
        manager.setEnabled(false, for: "mock.b")
        #expect(manager.pageIDs == [["mock.a"]])

        manager.enable("mock.b", atPage: 0, index: 0)
        #expect(manager.pageIDs == [["mock.b", "mock.a"]])
    }

    @Test func reinitialiser() {
        let manager = makeManager()
        manager.move("mock.b", toPage: 1, index: 0)
        manager.resetLayout()
        #expect(manager.pageIDs == [["mock.a", "mock.b"]])
    }
}
