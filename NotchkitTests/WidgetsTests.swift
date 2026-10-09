import Foundation
import SwiftUI
import Testing
@testable import Notchkit

struct PaginationTests {
    @Test func cartesRepartiesSansDepasserLaCapacite() {
        // Musique (2) + Horloge (1) + Batterie (1) | Calendrier (2) + Météo (1,5)
        #expect(NotchLayout.paginate(weights: [2, 1, 1, 2, 1.5], capacity: 4) == [[0, 1, 2], [3, 4]])
    }

    @Test func carteTropLargeSeule() {
        #expect(NotchLayout.paginate(weights: [5, 1], capacity: 4) == [[0], [1]])
        #expect(NotchLayout.paginate(weights: [], capacity: 4) == [])
    }
}

struct CalendarScheduleTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func event(_ id: String, startIn minutes: Double, duration: Double = 60, allDay: Bool = false) -> CalendarEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return CalendarEvent(id: id, title: id, start: start, end: start.addingTimeInterval(duration * 60),
                             isAllDay: allDay, color: .blue, calendarTitle: "")
    }

    @Test func evenementsAVenirTriesEtLimites() {
        let events = [
            event("fini", startIn: -120),
            event("plus tard", startIn: 90),
            event("bientôt", startIn: 20),
            event("journée", startIn: -300, duration: 24 * 60, allDay: true),
        ]
        let upcoming = CalendarSchedule.upcoming(events, at: now, limit: 2)
        #expect(upcoming.map(\.id) == ["journée", "bientôt"])
    }

    @Test func rappelDixMinutesAvant() {
        #expect(CalendarSchedule.reminderEvent(in: [event("a", startIn: 11)], at: now) == nil)
        #expect(CalendarSchedule.reminderEvent(in: [event("a", startIn: 9)], at: now)?.id == "a")
        #expect(CalendarSchedule.reminderEvent(in: [event("a", startIn: -0.5)], at: now)?.id == "a")
        #expect(CalendarSchedule.reminderEvent(in: [event("a", startIn: -2)], at: now) == nil)
        // Pas de rappel pour les journées entières.
        #expect(CalendarSchedule.reminderEvent(in: [event("j", startIn: 5, allDay: true)], at: now) == nil)
    }

    @Test func prochainReveilAuPremierChangement() {
        // Événement dans 30 min : on se réveille au début du rappel (dans 20 min).
        let next = CalendarSchedule.nextBoundary(after: now, events: [event("a", startIn: 30)])
        #expect(next == now.addingTimeInterval(20 * 60))
    }
}

struct WeatherDecodingTests {
    let json = """
    {"utc_offset_seconds":7200,
     "current":{"time":"2026-10-04T10:15","interval":900,"temperature_2m":14.8,"apparent_temperature":13.9,"weather_code":3,"is_day":1},
     "hourly":{"time":["2026-10-04T10:00","2026-10-04T11:00"],"temperature_2m":[14.6,15.6],"weather_code":[3,61],"is_day":[1,1]},
     "daily":{"time":["2026-10-04"],"temperature_2m_max":[23.1],"temperature_2m_min":[11.4],"precipitation_probability_max":[20]}}
    """

    @Test func decodageReponseOpenMeteo() throws {
        let snapshot = try OpenMeteoForecast.decode(Data(json.utf8)).snapshot()
        #expect(snapshot.temperature == 14.8)
        #expect(snapshot.code == 3)
        #expect(snapshot.isDay)
        #expect(snapshot.high == 23.1)
        #expect(snapshot.low == 11.4)
        #expect(snapshot.precipitationChance == 20)
        #expect(snapshot.hours.count == 2)
        // 10:00 heure locale (UTC+2) = 08:00 UTC.
        let expected = ISO8601DateFormatter().date(from: "2026-10-04T08:00:00Z")
        #expect(snapshot.hours.first?.date == expected)
        #expect(snapshot.hours.last?.code == 61)
    }

    @Test func symbolesJourEtNuit() {
        #expect(WeatherCondition.symbol(code: 0, isDay: true) == "sun.max.fill")
        #expect(WeatherCondition.symbol(code: 0, isDay: false) == "moon.stars.fill")
        #expect(WeatherCondition.symbol(code: 95, isDay: true) == "cloud.bolt.rain.fill")
        #expect(WeatherCondition.symbol(code: 1234, isDay: true) == "cloud.fill")
    }
}

struct DayProgressTests {
    @Test func progressionBorneeEntreDebutEtFin() {
        #expect(DayProgress.fraction(at: 7 * 60, start: 480, end: 1080) == 0)
        #expect(DayProgress.fraction(at: 13 * 60, start: 480, end: 1080) == 0.5)
        #expect(DayProgress.fraction(at: 20 * 60, start: 480, end: 1080) == 1)
        #expect(DayProgress.fraction(at: 600, start: 600, end: 600) == 0)
    }

    @Test func tempsRestantEtLibelle() {
        #expect(DayProgress.remaining(at: 1020, end: 1080) == 60)
        #expect(DayProgress.remaining(at: 1100, end: 1080) == 0)
        #expect(DayProgress.label(480) == "8:00")
        #expect(DayProgress.label(1110) == "18:30")
    }
}
