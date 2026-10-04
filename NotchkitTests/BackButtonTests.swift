import Foundation
import Testing
@testable import Notchkit

struct AppSwitchHistoryTests {
    func app(_ pid: pid_t, _ name: String, _ id: String? = nil) -> RecentApp {
        RecentApp(processIdentifier: pid, bundleIdentifier: id ?? "app.\(name)", name: name)
    }

    @Test func appPrecedente() {
        var history = AppSwitchHistory()
        history.activated(app(1, "Safari"))
        #expect(history.previous == nil)
        history.activated(app(2, "Mail"))
        #expect(history.previous?.name == "Safari")
        history.activated(app(1, "Safari"))
        #expect(history.previous?.name == "Mail")
    }

    @Test func notchkitEtFenetresSystemeIgnorees() {
        var history = AppSwitchHistory()
        history.activated(app(1, "Safari"))
        let notchkitChanged = history.activated(app(9, "Notchkit", "com.andeolchenaux.notchkit"))
        let agentChanged = history.activated(app(8, "SecurityAgent", "com.apple.SecurityAgent"))
        #expect(!notchkitChanged)
        #expect(!agentChanged)
        #expect(history.apps.count == 1)
    }

    @Test func appQuitteeRetiree() {
        var history = AppSwitchHistory()
        history.activated(app(1, "Safari"))
        history.activated(app(2, "Mail"))
        history.terminated(processIdentifier: 1)
        #expect(history.previous == nil)
    }
}
