import Foundation
import Testing
@testable import LevelUpKit

struct ModelCodingTests {
    @Test func localDateRoundTripsAndCompares() throws {
        let date = try #require(LocalDate(string: "2026-10-09"))
        #expect(date.description == "2026-10-09")
        #expect(date < LocalDate(year: 2026, month: 10, day: 10))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Almaty")!
        #expect(date.adding(days: 23, calendar: calendar).description == "2026-11-01")
        #expect(LocalDate(date.date(calendar: calendar), calendar: calendar) == date)
    }

    @Test func taskUpdateSendsNullsToClearFields() throws {
        let task = try JSONCoding.makeDecoder().decode(TaskItem.self, from: Fixtures.task)
        var update = TaskUpdate(task)
        update.dueDate = nil
        update.notes = nil

        let json = try #require(
            JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(update)) as? [String: Any]
        )

        #expect(json["due_date"] is NSNull)
        #expect(json["notes"] is NSNull)
        #expect(json["due_time"] as? String == "09:30")
        #expect(json["status"] as? String == "todo")
    }

    @Test func captureResultDecodesItemsAndConflicts() throws {
        let result = try JSONCoding.makeDecoder().decode(CaptureResult.self, from: Fixtures.captureResult)

        let capture = result.capture
        #expect(capture.status == .parsed)
        #expect(capture.items.count == 2)
        let task = capture.items[0]
        #expect(task.kind == .task)
        #expect(task.dueDate == LocalDate(year: 2026, month: 10, day: 16))
        #expect(task.conflict?.end == "14:00")
        let fact = capture.items[1]
        #expect(fact.kind == .profileFact)
        #expect(fact.schedule?.weekdays == [.fri])
    }

    @Test func unknownItemTypeDoesNotBreakDecoding() throws {
        let json = Data(#"{"type":"habit","title":"Пить воду","remind":false,"priority":"normal","include":true,"supported":false}"#.utf8)

        let item = try JSONCoding.makeDecoder().decode(CaptureItem.self, from: json)

        #expect(item.kind == nil)
        #expect(item.type == "habit")
    }

    @Test func capturedItemEncodesBackInApiFormat() throws {
        let result = try JSONCoding.makeDecoder().decode(CaptureResult.self, from: Fixtures.captureResult)

        let json = try #require(
            JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(result.capture.items[1])) as? [String: Any]
        )

        #expect(json["fact_category"] as? String == "schedule")
        #expect((json["schedule"] as? [String: Any])?["weekdays"] as? [String] == ["FRI"])
        #expect(json["id"] == nil)
    }
}

extension ModelCodingTests {
    @Test func taskUpdateEncodesRecurrence() throws {
        var task = try JSONCoding.makeDecoder().decode(TaskItem.self, from: Fixtures.task)
        task.recurrence = Recurrence(freq: .weekly, weekdays: [.mon, .fri])

        let json = try #require(
            JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(TaskUpdate(task))) as? [String: Any]
        )

        let recurrence = try #require(json["recurrence"] as? [String: Any])
        #expect(recurrence["freq"] as? String == "weekly")
        #expect(recurrence["weekdays"] as? [String] == ["MON", "FRI"])
    }

    @Test func progressAndJournalDecode() throws {
        let progress = try JSONCoding.makeDecoder().decode(LevelProgress.self, from: Data("""
        {"level":3,"xp_in_level":40,"xp_for_next_level":520,"total_xp":423,"today_xp":25,
         "recent":[{"source_type":"task","amount":15,"title":"Отчёт","created_at":"2026-10-10T08:00:00.5Z"}]}
        """.utf8))
        #expect(progress.level == 3)
        #expect(progress.xpForNextLevel == 520)
        #expect(progress.recent.first?.title == "Отчёт")

        let entry = try JSONCoding.makeDecoder().decode(JournalEntry.self, from: Data("""
        {"id":"0c7d1b9a-3a39-4f3e-9d36-6a5d2b8f1e22","entry_date":"2026-10-10","text":"Хороший день",
         "summary":null,"mood":4,"energy":null,"tags":["спорт"],"capture_id":null,
         "created_at":"2026-10-10T08:00:00Z","updated_at":"2026-10-10T08:00:00Z"}
        """.utf8))
        #expect(entry.entryDate == LocalDate(year: 2026, month: 10, day: 10))
        #expect(entry.mood == 4)
    }

    @Test func journalInputSendsNullMood() throws {
        let input = JournalInput(entryDate: LocalDate(year: 2026, month: 10, day: 10), text: "Текст")

        let json = try #require(
            JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(input)) as? [String: Any]
        )

        #expect(json["mood"] is NSNull)
        #expect(json["entry_date"] as? String == "2026-10-10")
    }

    @Test func phaseOneCaptureItemStillDecodes() throws {
        // Записи, сохранённые до этапа 2, не содержат новых полей.
        let json = Data(#"{"type":"shopping","title":"Молоко, хлеб","include":true,"supported":false}"#.utf8)

        let item = try JSONCoding.makeDecoder().decode(CaptureItem.self, from: json)

        #expect(item.products.isEmpty)
        #expect(item.priority == .normal)
    }
}

private enum Fixtures {
    static let task = Data("""
    {"id":"9b2b1d7c-6a0e-4a43-9a52-0f3c7c1f6f10","title":"Позвонить в банк","notes":"номер в почте",
     "status":"todo","priority":"high","due_date":"2026-10-10","due_time":"09:30","remind":true,
     "remind_at":"2026-10-10T04:30:00Z","reminders":["2026-10-10T04:30:00Z"],"recurrence":null,
     "difficulty":1,"position":-1791568800.5,"completed_at":null,
     "capture_id":null,"created_at":"2026-10-09T18:00:00.123456Z","updated_at":"2026-10-09T18:00:00Z"}
    """.utf8)

    static let captureResult = Data("""
    {"capture":{"id":"0c7d1b9a-3a39-4f3e-9d36-6a5d2b8f1e22","text":"Созвон в пятницу в 13, по пятницам жума",
      "source":"voice","status":"parsed","error_code":null,"reply":"Задача и факт о тебе","provider":"gemini",
      "model":"gemini-3.5-flash","created":[],"created_at":"2026-10-09T18:00:00Z",
      "items":[
        {"type":"task","title":"Созвон с командой","details":null,"due_date":"2026-10-16","due_time":"13:00",
         "remind":true,"priority":"normal","difficulty":2,"fact_category":null,"schedule":null,"include":true,
         "supported":true,"conflict":{"fact_id":"5f0b1c2d-1111-4a43-9a52-0f3c7c1f6f10","fact_text":"Жума",
         "start":"12:30","end":"14:00"}},
        {"type":"profile_fact","title":"По пятницам 12:30–14:00 жума","details":null,"due_date":null,
         "due_time":null,"remind":false,"priority":"normal","difficulty":null,"fact_category":"schedule",
         "schedule":{"weekdays":["FRI"],"start":"12:30","end":"14:00","busy":true},"include":true,
         "supported":true,"conflict":null}]},
     "tasks":[],"facts":[],"journal":[],"shopping":[],"xp_gained":0}
    """.utf8)
}
