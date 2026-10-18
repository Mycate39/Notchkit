import Foundation
import Testing
@testable import Notchkit

/// Module Agents et widgets pleine page.
struct AgentsTests {
    @Test func widgetPleinePageSeulSurSaPage() {
        // Le widget pleine page sépare sa page en trois : avant lui, lui seul, après lui.
        let pages = WidgetLayoutEngine.isolate(["agents"], in: [["music", "agents", "clock"], ["weather"]])
        #expect(pages == [["music"], ["agents"], ["clock"], ["weather"]])
        // Déjà seul, ou absent : rien ne change.
        #expect(WidgetLayoutEngine.isolate(["agents"], in: [["agents"], ["clock"]]) == [["agents"], ["clock"]])
        #expect(WidgetLayoutEngine.isolate([], in: [["music", "clock"]]) == [["music", "clock"]])
    }

    @Test func paginationAutomatiqueIsoleLeWidgetPleinePage() {
        let pages = WidgetLayoutEngine.pages(activeIDs: ["music", "agents", "clock"],
                                             weights: ["music": 1, "agents": 4, "clock": 1],
                                             layout: nil, capacity: 4, fullPage: ["agents"])
        #expect(pages.contains(["agents"]))
        #expect(pages.flatMap { $0 }.sorted() == ["agents", "clock", "music"])
    }

    @Test func humeurDeLaMascotteSelonLaSession() {
        var session = ClaudeSession(id: "a", state: .working, lastEventAt: Date())
        #expect(AgentsModule.mood(for: session, celebrating: false) == .working)
        session.state = .waitingForPermission
        #expect(AgentsModule.mood(for: session, celebrating: true) == .waiting)
        session.state = .finished
        #expect(AgentsModule.mood(for: session, celebrating: true) == .happy)
        #expect(AgentsModule.mood(for: session, celebrating: false) == .idle)
        #expect(AgentsModule.mood(for: nil, celebrating: false) == .idle)
    }
}
