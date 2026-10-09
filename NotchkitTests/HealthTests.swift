import Foundation
import Testing
@testable import Notchkit

struct ActivityClockTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func periodeActiveEtPause() {
        #expect(ActivityClock.streakStart(previous: nil, idle: 10, now: now) == now.addingTimeInterval(-10))
        let start = now.addingTimeInterval(-600)
        #expect(ActivityClock.streakStart(previous: start, idle: 30, now: now) == start)
        #expect(ActivityClock.streakStart(previous: start, idle: 400, now: now) == nil)
        #expect(ActivityClock.isActive(idle: 60))
        #expect(!ActivityClock.isActive(idle: 200))
    }

    @Test func secondesDepuisDerniereActiviteLisible() {
        #expect(ActivityClock.secondsSinceLastInput >= 0)
    }
}

struct HealthRulesTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func pauseApres50MinPuisToutesLes10() {
        let start = now.addingTimeInterval(-49 * 60)
        #expect(!HealthRules.shouldRemindBreak(streakStart: start, lastReminder: nil, now: now))
        let longStart = now.addingTimeInterval(-55 * 60)
        #expect(HealthRules.shouldRemindBreak(streakStart: longStart, lastReminder: nil, now: now))
        #expect(!HealthRules.shouldRemindBreak(streakStart: longStart, lastReminder: now.addingTimeInterval(-5 * 60), now: now))
        #expect(HealthRules.shouldRemindBreak(streakStart: longStart, lastReminder: now.addingTimeInterval(-11 * 60), now: now))
        #expect(!HealthRules.shouldRemindBreak(streakStart: nil, lastReminder: nil, now: now))
    }

    @Test func eauToutesLesHeures() {
        #expect(!HealthRules.shouldRemindWater(lastDrink: now.addingTimeInterval(-30 * 60), lastReminder: nil, now: now))
        #expect(HealthRules.shouldRemindWater(lastDrink: now.addingTimeInterval(-61 * 60), lastReminder: nil, now: now))
        #expect(!HealthRules.shouldRemindWater(lastDrink: now.addingTimeInterval(-90 * 60),
                                               lastReminder: now.addingTimeInterval(-10 * 60), now: now))
    }
}

struct ScreenTimeLogTests {
    @Test func cumulParAppEtParJour() {
        var log = ScreenTimeLog()
        log.add(30, app: "a", day: "2026-10-09")
        log.add(60, app: "b", day: "2026-10-09")
        log.add(60, app: "a", day: "2026-10-09")
        #expect(log.total(day: "2026-10-09") == 150)
        #expect(log.topApps(day: "2026-10-09").map(\.app) == ["a", "b"])
        #expect(ScreenTimeFormat.duration(3900) == "1 h 05")
        #expect(ScreenTimeFormat.duration(600) == "10 min")
    }

    @Test func neGardeQueLesDerniersJours() {
        var log = ScreenTimeLog()
        for day in 1...40 { log.add(1, app: "a", day: String(format: "2026-09-%02d", day % 30 + 1)) }
        log.add(1, app: "a", day: "2026-10-09")
        log.prune(keeping: 3)
        #expect(log.days.keys.sorted() == ["2026-09-29", "2026-09-30", "2026-10-09"])
    }
}
