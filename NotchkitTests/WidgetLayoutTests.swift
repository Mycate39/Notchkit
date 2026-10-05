import Foundation
import Testing
@testable import Notchkit

struct WidgetLayoutEngineTests {
    let weights: [String: CGFloat] = ["music": 2, "clock": 1, "battery": 1, "calendar": 2, "weather": 1.5]
    let active = ["music", "clock", "battery", "calendar", "weather"]

    @Test func sansDispositionRepartitionAutomatique() {
        let pages = WidgetLayoutEngine.pages(activeIDs: active, weights: weights, layout: nil, capacity: 4)
        #expect(pages == [["music", "clock", "battery"], ["calendar", "weather"]])
    }

    @Test func dispositionUtilisateurRespecteeEtNouveauxModulesAjoutes() {
        let layout = WidgetLayout(pages: [["weather", "clock"], ["music"]])
        let pages = WidgetLayoutEngine.pages(activeIDs: active, weights: weights, layout: layout, capacity: 4)
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
        #expect(WidgetSize.mini.weight == 0.5)
        // Sans empilement, huit colonnes de largeur 0,5 tiennent sur une page.
        #expect(NotchLayout.paginate(weights: Array(repeating: 0.5, count: 9), capacity: 4) == [Array(0..<8), [8]])
    }

    @Test func deuxMiniConsecutifsSEmpilent() {
        #expect(WidgetColumns.make(sizes: [.mini, .mini, .small, .mini]) == [[0, 1], [2], [3]])
        #expect(WidgetColumns.effectiveWeights(sizes: [.mini, .mini, .mini]) == [0.5, 0, 0.5])
        // 16 Mini tiennent sur une page (8 colonnes de 2).
        let pages = WidgetLayoutEngine.pages(activeIDs: (0..<17).map(String.init),
                                             weights: Dictionary(uniqueKeysWithValues: (0..<17).map { (String($0), CGFloat(0.5)) }),
                                             layout: nil, capacity: 4)
        #expect(pages.first?.count == 16)
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

@MainActor
struct AppearanceTests {
    @Test func tailleDeLEncocheEtCapacite() {
        let saved = NotchLayout.appearance
        defer { NotchLayout.appearance = saved }
        var appearance = NotchAppearance()
        appearance.size = .large
        NotchLayout.appearance = appearance
        #expect(NotchLayout.expandedSize.width == 760)
        #expect(NotchLayout.pageCapacity == 5)
    }

    @Test func apparenceEnregistreeEtTolerante() throws {
        var settings = AppSettings()
        settings.appearance.background = .custom
        settings.appearance.accent = StoredColor(red: 1, green: 0.5, blue: 0)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.appearance == settings.appearance)
        // Anciens réglages sans apparence : valeurs par défaut.
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"simulateNotch": false}"#.utf8))
        #expect(old.appearance == NotchAppearance())
    }
}

struct CustomSizeTests {
    @Test func taillePersonnalisee() {
        var appearance = NotchAppearance()
        appearance.size = .custom
        appearance.customWidth = 800
        appearance.customHeight = 230
        #expect(appearance.expandedSize == CGSize(width: 800, height: 230))
        #expect(appearance.pageCapacity == 5)
        appearance.customWidth = 480
        #expect(appearance.pageCapacity == 3)
    }
}

struct LayoutPresetTests {
    @Test func dispositionsCoherentes() {
        let known: Set<String> = ["music", "clock", "battery", "calendar", "weather", "claude", "shelf", "airpods",
                                  "activities", "clipboard", "systemhud", "back", "videodownload"]
        for preset in LayoutPreset.all {
            #expect(preset.enabledIDs.isSubset(of: known), "module inconnu dans \(preset.id)")
            #expect(Set(preset.sizes.keys) == preset.enabledIDs, "tailles incomplètes dans \(preset.id)")
            // Chaque page tient dans la largeur standard (4), empilement des Mini compris.
            for page in preset.pages {
                let used = WidgetColumns.effectiveWeights(sizes: page.map { preset.sizes[$0] ?? .small }).reduce(0, +)
                #expect(used <= 4, "page trop large dans \(preset.id)")
            }
        }
    }
}

@MainActor
struct PresetApplyTests {
    @Test func appliquerPuisAnnuler() {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "notchkit.tests.\(UUID().uuidString)")!)
        let manager = ModuleManager(settings: settings, entitlements: EntitlementManager(),
                                    availableModules: [MockModuleA.self, MockModuleB.self])
        manager.reload()
        let preset = LayoutPreset(id: "t", name: "T", summary: "", symbol: "a", pages: [["mock.b"]], sizes: ["mock.b": .large])
        manager.apply(preset)
        #expect(manager.pageIDs == [["mock.b"]])
        #expect(manager.size(for: "mock.b") == .large)
        manager.undoPreset()
        #expect(manager.pageIDs == [["mock.a"]])
    }
}
