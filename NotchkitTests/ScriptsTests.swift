import Foundation
import Testing
@testable import Notchkit

struct ScriptsTests {
    @Test func formulaireDeCurlLuAvecSesEspacesEtAccents() {
        let fields = ClaudeHookServer.formFields("action=notify&title=Build%20termin%C3%A9&message=a+b&empty=")
        #expect(fields["title"] as? String == "Build terminé")
        #expect(fields["message"] as? String == "a b")
        #expect(fields["empty"] as? String == "")
    }

    @Test func demandeLueAvecSesValeursParDefaut() throws {
        let request = try #require(ScriptRequest(fields: ["action": "progress", "id": "export", "progress": "42,5", "title": " "]))
        #expect(request.action == .progress)
        #expect(request.progress == 0.425)
        #expect(request.title == nil)
        #expect(ScriptRequest(fields: ["action": "explode"]) == nil)
        #expect(try #require(ScriptRequest(fields: ["action": "end", "status": "failure"])).succeeded == false)
        #expect(try #require(ScriptRequest(fields: ["action": "end"])).succeeded)
    }

    @Test func activiteSuivieDuDebutALaFin() throws {
        var tracker = ScriptActivityTracker()
        let start = Date(timeIntervalSince1970: 1000)
        #expect(tracker.apply(try #require(ScriptRequest(fields: ["action": "start", "id": "t", "title": "npm test"])), at: start) == .none)
        tracker.apply(try #require(ScriptRequest(fields: ["action": "progress", "id": "t", "progress": "50"])), at: start.addingTimeInterval(5))
        #expect(tracker.ordered.first?.progress == 0.5)
        #expect(tracker.ordered.first?.title == "npm test")

        let outcome = tracker.apply(try #require(ScriptRequest(fields: ["action": "end", "id": "t", "status": "failure"])),
                                    at: start.addingTimeInterval(65))
        #expect(outcome == .finished(title: "npm test", message: nil, succeeded: false, duration: 65))
        #expect(tracker.activities.isEmpty)
    }

    @Test func notificationSansTitreGardeSonMessage() throws {
        var tracker = ScriptActivityTracker()
        let outcome = tracker.apply(try #require(ScriptRequest(fields: ["action": "notify", "message": "Hello"])))
        #expect(outcome == .notification(title: "Hello", message: nil, symbol: "bell.fill", colorName: nil))
    }

    @Test func activitesOublieesApresUneHeure() throws {
        var tracker = ScriptActivityTracker()
        let start = Date(timeIntervalSince1970: 0)
        tracker.apply(try #require(ScriptRequest(fields: ["action": "start", "id": "a"])), at: start)
        tracker.expireStale(at: start.addingTimeInterval(ScriptActivity.staleInterval + 1))
        #expect(tracker.activities.isEmpty)
    }

    @Test func dureesLisibles() {
        #expect(ScriptActivityTracker.durationText(42) == String(localized: "42 s"))
        #expect(ScriptActivityTracker.durationText(185) == String(localized: "3 min 05"))
    }

    @Test func scriptDeLaCommande() {
        let script = ScriptCommandInstaller.script(port: 52_732, token: "xyz")
        #expect(script.hasPrefix("#!/bin/sh"))
        #expect(script.contains("URL='http://127.0.0.1:52732/notchkit/notify'"))
        #expect(script.contains("TOKEN='xyz'"))
        // Le texte d'aide se termine bien (ligne « EOF » au début de la ligne).
        #expect(script.contains("\nEOF\n"))
    }
}
