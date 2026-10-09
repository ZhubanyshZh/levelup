import Foundation
import Testing
@testable import LevelUpKit

struct WidgetSnapshotTests {
    private let today = LocalDate(year: 2026, month: 10, day: 9)  // пятница

    private func task(_ title: String, due: LocalDate?, time: String? = nil, doing: Bool = false) -> WidgetSnapshot.TaskEntry {
        WidgetSnapshot.TaskEntry(id: UUID(), title: title, dueDate: due, dueTime: time, isDoing: doing)
    }

    @Test func dayShowsOverdueTodayAndInProgressTasks() {
        let snapshot = WidgetSnapshot(isSignedIn: true, tasks: [
            task("Просрочено", due: today.adding(days: -2)),
            task("Сегодня", due: today),
            task("Завтра", due: today.adding(days: 1)),
            task("В работе", due: nil, doing: true),
            task("Когда-нибудь", due: nil),
        ])

        #expect(snapshot.tasks(on: today).map(\.title) == ["Просрочено", "Сегодня", "В работе"])
        // После полуночи завтрашняя задача становится задачей дня — без приложения.
        #expect(snapshot.tasks(on: today.adding(days: 1)).map(\.title).contains("Завтра"))
    }

    @Test func taskCheckedInWidgetStaysCrossedOutOnlyThatDay() {
        var snapshot = WidgetSnapshot(isSignedIn: true, tasks: [task("Отчёт", due: today)])
        let id = snapshot.tasks[0].id

        snapshot.apply([.task(id: id, done: true)], today: today)

        #expect(snapshot.tasks(on: today).first?.doneOn == today)
        #expect(snapshot.tasks(on: today.adding(days: 1)).isEmpty)
    }

    @Test func nextTimedTaskSkipsPastAndChecked() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Almaty")!
        var snapshot = WidgetSnapshot(isSignedIn: true, tasks: [
            task("Утро", due: today, time: "08:00"),
            task("Созвон", due: today, time: "15:00"),
            task("Спортзал", due: today, time: "19:00"),
        ])
        snapshot.apply([.task(id: snapshot.tasks[1].id, done: true)], today: today)
        let noon = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12)))

        #expect(snapshot.nextTimedTask(after: noon, calendar: calendar)?.title == "Спортзал")
    }

    @Test func journalStreakDoesNotBreakBeforeTheDayEnds() {
        let snapshot = WidgetSnapshot(isSignedIn: true, journalDays: [
            today.adding(days: -3), today.adding(days: -2), today.adding(days: -1),
        ])

        #expect(snapshot.journalStreak(on: today) == 3)
        #expect(!snapshot.hasJournal(on: today))
        #expect(snapshot.journalStreak(on: today.adding(days: 1)) == 0)
    }

    @Test func busySlotsFollowWeekday() {
        let snapshot = WidgetSnapshot(isSignedIn: true, busy: [
            .init(title: "Жума", weekdays: [.fri], start: "12:30", end: "14:00"),
            .init(title: "Работа", weekdays: [.mon, .tue, .wed, .thu, .fri], start: "09:00", end: "18:00"),
        ])

        #expect(today.weekday == .fri)
        #expect(snapshot.busySlots(on: today).map(\.title) == ["Работа", "Жума"])
        #expect(snapshot.busySlots(on: today.adding(days: 1)).isEmpty)
    }

    @Test func todayXpBelongsToItsDay() {
        var snapshot = WidgetSnapshot(isSignedIn: true)
        snapshot.apply(LevelProgress(level: 3, xpInLevel: 40, xpForNextLevel: 520, totalXp: 423, todayXp: 25, recent: []), today: today)

        #expect(snapshot.xpToday(on: today) == 25)
        #expect(snapshot.xpToday(on: today.adding(days: 1)) == 0)
    }

    @Test func snapshotFromOlderAppVersionStillDecodes() throws {
        let old = Data(#"{"is_signed_in":true,"display_name":"Жубаныш","level":4,"xp":10,"xp_for_next_level":800,"updated_at":"2026-10-09T10:00:00Z"}"#.utf8)

        let snapshot = try JSONCoding.makeDecoder().decode(WidgetSnapshot.self, from: old)

        #expect(snapshot.level == 4)
        #expect(snapshot.tasks.isEmpty)
    }

    @Test func routesRoundTripThroughURLs() {
        let routes: [AppRoute] = [.capture(.voice), .capture(.text), .newJournalEntry, .journal, .shopping, .today]
        for route in routes {
            #expect(AppRoute(url: route.url) == route)
        }
        #expect(AppRoute(url: URL(string: "com.googleusercontent.apps.123:/oauth")!) == nil)
    }

    @Test func weekdayOfLocalDate() {
        #expect(LocalDate(year: 2026, month: 10, day: 5).weekday == .mon)
        #expect(LocalDate(year: 2026, month: 10, day: 11).weekday == .sun)
    }
}
