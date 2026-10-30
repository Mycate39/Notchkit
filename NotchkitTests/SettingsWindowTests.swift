import Foundation
import Testing
@testable import Notchkit

/// Fenêtre des réglages : réglages tolérants, licences des composants tiers, titre des pages.
struct SettingsWindowTests {
    @Test func valeurIllisibleNeFaitPasPerdreLesReglages() throws {
        // Une valeur d'un mauvais type reprend sa valeur par défaut ; les autres réglages sont gardés.
        let json = #"{"hoverOpenDelay": "vite", "hapticsEnabled": false, "showsMenuBarIcon": 3}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.hoverOpenDelay == AppSettings().hoverOpenDelay)
        #expect(settings.hapticsEnabled == false)
        #expect(settings.showsMenuBarIcon == AppSettings().showsMenuBarIcon)
    }

    @Test func licencesCopieesDansLApp() throws {
        for (name, author) in [("LICENSE", "Jonas van den Berg"), ("Sparkle-LICENSE", "Andy Matuschak")] {
            let url = try #require(Bundle.main.url(forResource: name, withExtension: "txt"))
            #expect(try String(contentsOf: url, encoding: .utf8).contains(author))
        }
    }

    @Test @MainActor func titreDeLaPageOuverte() throws {
        let suite = "notchkit.tests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: try #require(UserDefaults(suiteName: suite)))
        let manager = ModuleManager(settings: settings, entitlements: EntitlementManager(), availableModules: [])
        #expect(SettingsTab.general.title(in: manager) == String(localized: "Général"))
        #expect(SettingsTab.about.title(in: manager) == String(localized: "À propos"))
        // Module inconnu : la page reste sous « Widgets ».
        #expect(SettingsTab.module("inconnu").title(in: manager) == String(localized: "Widgets"))
    }
}
