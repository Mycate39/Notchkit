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
    @Test func anciensReglagesAvecTailleSeChargentToujours() throws {
        // Les versions précédentes enregistraient une taille d'encoche : elle est ignorée.
        let json = #"{"size": "large", "customWidth": 800, "customHeight": 230, "background": "glass"}"#
        let appearance = try JSONDecoder().decode(NotchAppearance.self, from: Data(json.utf8))
        #expect(appearance.background == .glass)
        // Fonds retirés (Graphite, Personnalisé) : retour au noir.
        let old = try JSONDecoder().decode(NotchAppearance.self, from: Data(#"{"background": "graphite"}"#.utf8))
        #expect(old.background == .black)
    }

    @Test func apparenceEnregistreeEtTolerante() throws {
        var settings = AppSettings()
        settings.appearance.background = .glass
        settings.appearance.accent = StoredColor(red: 1, green: 0.5, blue: 0)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.appearance == settings.appearance)
        // Anciens réglages sans apparence : valeurs par défaut.
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"simulateNotch": false}"#.utf8))
        #expect(old.appearance == NotchAppearance())
    }
}

struct PageSizeTests {
    @Test func largeurSuitLesWidgetsDeLaPage() {
        let one = NotchLayout.pageSize(moduleIDs: ["clock"], sizes: [.small], fullPage: false, glass: false)
        let two = NotchLayout.pageSize(moduleIDs: ["clock", "weather"], sizes: [.small, .large], fullPage: false, glass: false)
        let full = NotchLayout.pageSize(moduleIDs: ["a", "b", "c", "d"], sizes: [.small, .small, .small, .small],
                                        fullPage: false, glass: false)
        #expect(one.width < two.width && two.width < full.width)
        #expect(full == NotchLayout.defaultExpandedSize)
    }

    @Test func hauteurSuitLePlusGrandWidget() {
        #expect(NotchLayout.expandedHeight(sizes: [.mini, .mini]) == NotchLayout.miniExpandedHeight)
        #expect(NotchLayout.expandedHeight(sizes: [.mini, .small]) == NotchLayout.expandedHeight)
        #expect(NotchLayout.expandedHeight(sizes: [.medium]) == NotchLayout.expandedHeight)
        #expect(NotchLayout.expandedHeight(sizes: [.small, .large]) == NotchLayout.largeExpandedHeight)
        let mini = NotchLayout.pageSize(moduleIDs: ["clock"], sizes: [.mini], fullPage: false, glass: false)
        let small = NotchLayout.pageSize(moduleIDs: ["clock"], sizes: [.small], fullPage: false, glass: false)
        #expect(mini.height < small.height)
        #expect(mini.width <= small.width)
    }

    @Test func deuxMiniEmpilesPrennentUneSeuleColonne() {
        let pair = NotchLayout.pageSize(moduleIDs: ["a", "b", "c"], sizes: [.mini, .mini, .large], fullPage: false, glass: false)
        let alone = NotchLayout.pageSize(moduleIDs: ["a", "c"], sizes: [.mini, .large], fullPage: false, glass: false)
        #expect(pair == alone)
    }

    @Test func pagePleineEtVerreSontPlusLarges() {
        let agents = NotchLayout.pageSize(moduleIDs: ["agents"], sizes: [.large], fullPage: true, glass: false)
        #expect(agents.width == NotchLayout.defaultExpandedSize.width)
        #expect(agents.height == NotchLayout.largeExpandedHeight)
        let glass = NotchLayout.pageSize(moduleIDs: ["a", "b"], sizes: [.small, .small], fullPage: false, glass: true)
        let black = NotchLayout.pageSize(moduleIDs: ["a", "b"], sizes: [.small, .small], fullPage: false, glass: false)
        #expect(glass.width > black.width)
        #expect(NotchLayout.maxExpandedSize.width >= glass.width)
    }
}

struct LayoutPresetTests {
    @Test func dispositionsCoherentes() {
        let known: Set<String> = ["music", "clock", "battery", "calendar", "weather", "agents", "shelf", "airpods",
                                  "activities", "clipboard", "systemhud", "videodownload"]
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

struct FlowLayoutTests {
    func arrange(_ widths: [CGFloat], maxWidth: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        FlowLayout.arrange(widths.map { CGSize(width: $0, height: 20) }, maxWidth: maxWidth, spacing: 8, lineSpacing: 8)
    }

    @Test func pastillesSurUneLigneQuandToutTient() {
        let result = arrange([50, 60, 70], maxWidth: 400)
        #expect(result.origins.map(\.x) == [0, 58, 126])
        #expect(result.origins.allSatisfy { $0.y == 0 })
        #expect(result.size == CGSize(width: 196, height: 20))
    }

    @Test func passeALaLigneSansComprimer() {
        let result = arrange([100, 100, 100], maxWidth: 220)
        #expect(result.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 108, y: 0), CGPoint(x: 0, y: 28)])
        #expect(result.size == CGSize(width: 208, height: 48))
    }

    @Test func elementTropLargeSeulSurSaLigne() {
        let result = arrange([300, 40], maxWidth: 200)
        #expect(result.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 28)])
        #expect(result.size.width == 300)
    }

    @Test func aucunElement() {
        #expect(arrange([], maxWidth: 200).size == .zero)
    }
}

/// Balayage des pages au trackpad : les pages suivent les doigts et se calent au relâchement.
struct PageSwipeTests {
    @Test func balayageHorizontalChangeDePage() {
        var swipe = PageSwipe()
        swipe.begin()
        let undecided = swipe.move(dx: -3, dy: 0.5)   // pas encore décidé : gardé pour les pages
        let horizontal = swipe.move(dx: -40, dy: 2)
        #expect(undecided && horizontal)
        #expect(swipe.isTracking)
        #expect(swipe.offset(page: 1, pageCount: 3) == -43)
        #expect(swipe.end(page: 1, pageCount: 3, pageWidth: 300) == 2)
        #expect(!swipe.isTracking)
    }

    @Test func pageViseeConnuePendantLeGeste() {
        var swipe = PageSwipe()
        swipe.begin()
        _ = swipe.move(dx: -20, dy: 0)
        #expect(swipe.target(page: 1, pageCount: 3, pageWidth: 300) == 1)   // sous le seuil (36)
        _ = swipe.move(dx: -20, dy: 0)
        #expect(swipe.target(page: 1, pageCount: 3, pageWidth: 300) == 2)   // seuil franchi : cran
        #expect(swipe.isTracking)
    }

    @Test func petitBalayageRevientSurPlace() {
        var swipe = PageSwipe()
        swipe.begin()
        _ = swipe.move(dx: 20, dy: 0)
        #expect(swipe.end(page: 1, pageCount: 3, pageWidth: 300) == 1)
    }

    @Test func resistanceAuxExtremitesSansDepasser() {
        var swipe = PageSwipe()
        swipe.begin()
        _ = swipe.move(dx: 100, dy: 0)
        #expect(swipe.offset(page: 0, pageCount: 3) == 100 * PageSwipe.edgeResistance)
        #expect(swipe.end(page: 0, pageCount: 3, pageWidth: 300) == 0)
    }

    @Test func gesteVerticalLaisseALaVue() {
        var swipe = PageSwipe()
        swipe.begin()
        _ = swipe.move(dx: 1, dy: -2)
        let vertical = swipe.move(dx: 1, dy: -6)
        let later = swipe.move(dx: -50, dy: 0)
        #expect(!vertical && !later)
        #expect(!swipe.isTracking)
        #expect(swipe.end(page: 1, pageCount: 3, pageWidth: 300) == 1)
    }
}
