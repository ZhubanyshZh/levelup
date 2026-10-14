import Foundation
import Testing
@testable import LevelUpKit

struct CoachTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Almaty")!
        return calendar
    }

    private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

    @Test func reportDecodesConflictAndAcceptedAction() throws {
        let json = Data("""
        {"id":"11111111-1111-1111-1111-111111111111","kind":"morning","period_start":"2026-10-12","goal_id":null,
         "title":"План","message":"Начни с малого","highlights":[],"reflection_question":null,"created_at":"2026-10-12T06:00:00Z",
         "actions":[{"id":"22222222-2222-2222-2222-222222222222","title":"Читать","notes":null,"due_date":"2026-10-12",
          "due_time":"10:00","duration_minutes":30,"difficulty":2,"sphere":"mind","task_id":null,
          "conflict":{"fact_id":"33333333-3333-3333-3333-333333333333","fact_text":"Работа","start":"09:00","end":"18:00"},
          "applied_id":"44444444-4444-4444-4444-444444444444"}]}
        """.utf8)
        let report = try JSONCoding.makeDecoder().decode(CoachReport.self, from: json)
        #expect(report.actions.first?.conflict?.factText == "Работа")
        #expect(report.actions.first?.appliedId != nil)
        #expect(report.periodStart == LocalDate(year: 2026, month: 10, day: 12))
    }

    @Test func unsupportedAnswerHasNoNumericResult() throws {
        let json = Data("""
        {"id":"11111111-1111-1111-1111-111111111111","capture_id":"22222222-2222-2222-2222-222222222222",
         "question":"Какая погода?","metric":"unsupported","start_date":"2026-10-01","end_date":"2026-10-12",
         "value":null,"currency":null,"explanation":"Погоды в записях нет"}
        """.utf8)
        let answer = try JSONCoding.makeDecoder().decode(CoachAnswer.self, from: json)
        #expect(answer.metric == .unsupported)
        #expect(answer.value == nil)
    }

    @Test func weeklyReportUsesLastCompleteWeekAndLocalDate() {
        // В UTC воскресенье, в Алматы уже понедельник.
        let now = date("2026-10-11T20:00:00Z")
        #expect(CoachKind.weekly.period(at: now, calendar: calendar) == LocalDate(year: 2026, month: 10, day: 5))
        #expect(CoachKind.morning.period(at: now, calendar: calendar) == LocalDate(year: 2026, month: 10, day: 12))
        #expect(CoachKind.current(at: date("2026-10-12T14:00:00Z"), calendar: calendar) == .evening)
    }

    @Test func remindersAvoidBusyTimeAndStayWithinCapacity() {
        let now = date("2026-10-12T02:00:00Z")
        let events = CoachReminderPlan.events(now: now, schedules: [
            Schedule(weekdays: [.mon], start: "09:00", end: "12:00"),
            Schedule(weekdays: [.mon], start: "21:00", end: "23:00"),
        ], calendar: calendar)
        let monday = events.filter { LocalDate($0.date, calendar: calendar).weekday == .mon }
        #expect(!monday.contains { $0.kind == .morning || $0.kind == .evening })
        #expect(monday.first?.kind == .weekly)
        #expect(calendar.component(.hour, from: monday.first!.date) == 12)
        #expect(events.count <= 15)
        #expect(events.allSatisfy { $0.date > now && $0.date < calendar.date(byAdding: .day, value: 7, to: now)! })
    }

    @Test func overnightBusyTimeCarriesIntoNextMorning() {
        let events = CoachReminderPlan.events(now: date("2026-10-12T02:00:00Z"), schedules: [
            Schedule(weekdays: [.sun], start: "23:00", end: "10:00"),
        ], calendar: calendar)
        let morning = events.first { $0.kind == .morning }!
        #expect(calendar.component(.hour, from: morning.date) == 10)
    }

    @Test func coachNotificationLinksKeepSelectedMode() {
        for kind in [CoachKind.morning, .evening, .weekly] {
            #expect(AppRoute(url: AppRoute.coach(kind).url) == .coach(kind))
        }
    }

    @Test func remindersRespectIndividualDaysIncludingOvernightOverrides() {
        let schedule = Schedule(weekdays: [.sun, .mon], start: "23:00", end: "10:00", dayIntervals: [
            DayInterval(weekday: .mon, start: "23:00", end: "11:00")
        ])
        let events = CoachReminderPlan.events(now: date("2026-10-12T02:00:00Z"), schedules: [schedule], calendar: calendar)
        let mornings = events.filter { $0.kind == .morning }
        let monday = mornings.first { LocalDate($0.date, calendar: calendar).weekday == .mon }!
        let tuesday = mornings.first { LocalDate($0.date, calendar: calendar).weekday == .tue }!
        #expect(calendar.component(.hour, from: monday.date) == 10)
        #expect(calendar.component(.hour, from: tuesday.date) == 11)
    }
}
