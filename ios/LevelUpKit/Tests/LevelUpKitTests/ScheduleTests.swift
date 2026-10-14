import Foundation
import Testing
@testable import LevelUpKit

struct ScheduleTests {
    @Test func legacySchedulesKeepSharedTime() throws {
        let data = Data(#"{"weekdays":["MON","FRI"],"start":"09:00","end":"18:00","busy":true}"#.utf8)
        let schedule = try JSONCoding.makeDecoder().decode(Schedule.self, from: data)
        #expect(schedule.dayIntervals.isEmpty)
        #expect(schedule.interval(on: .fri).start == "09:00")
    }

    @Test func individualTimesSurviveApiAndCacheRoundTrip() throws {
        let schedule = Schedule(weekdays: [.mon, .fri], start: "09:00", end: "18:00", dayIntervals: [
            DayInterval(weekday: .mon, start: "09:00", end: "18:00"),
            DayInterval(weekday: .fri, start: "23:00", end: "07:00")
        ])
        let encoded = try JSONCoding.makeEncoder().encode(schedule)
        let decoded = try JSONCoding.makeDecoder().decode(Schedule.self, from: encoded)
        #expect(decoded == schedule)
        #expect(decoded.interval(on: .mon).end == "18:00")
        #expect(decoded.interval(on: .fri).start == "23:00")
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect((json["day_intervals"] as? [[String: Any]])?.count == 2)
    }

    @Test func partialOverridesUseSharedTimeForOtherDays() throws {
        let schedule = Schedule(weekdays: [.mon, .fri], start: "09:00", end: "18:00", dayIntervals: [
            DayInterval(weekday: .fri, start: "12:30", end: "14:00")
        ])
        #expect(schedule.interval(on: .mon).end == "18:00")
        #expect(schedule.interval(on: .fri).end == "14:00")
    }

    @Test func widgetReceivesSeparateBusySlotsForEachDay() throws {
        let data = Data("""
        {"id":"11111111-1111-1111-1111-111111111111","category":"schedule","text":"Работа",
         "is_active":true,"created_at":"2026-10-14T08:00:00Z","updated_at":"2026-10-14T08:00:00Z",
         "schedule":{"weekdays":["MON","FRI"],"start":"09:00","end":"18:00","busy":true,
          "day_intervals":[{"weekday":"FRI","start":"12:30","end":"14:00"}]}}
        """.utf8)
        let fact = try JSONCoding.makeDecoder().decode(ProfileFact.self, from: data)
        let snapshot = WidgetSnapshot(isSignedIn: true, busy: WidgetSnapshot.busySlots([fact]))
        #expect(snapshot.busySlots(on: LocalDate(year: 2026, month: 10, day: 12)).first?.end == "18:00")
        #expect(snapshot.busySlots(on: LocalDate(year: 2026, month: 10, day: 16)).first?.end == "14:00")
        #expect(snapshot.busySlots(on: LocalDate(year: 2026, month: 10, day: 17)).isEmpty)
    }
}
