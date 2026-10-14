import Foundation
import Testing
@testable import LevelUpKit

struct TaskFilterTests {
    @Test func filtersRestoreFromSavedPreferencesAndResetPersists() throws {
        let suite = "TaskFilterTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        var filter = TaskFilter()
        filter.due = .nextSevenDays
        filter.priority = .high
        filter.sphere = "work"
        filter.goalID = UUID()
        preferences.set(filter.storedData, forKey: "tasksFilter")
        let reopened = try #require(UserDefaults(suiteName: suite))
        let restored = TaskFilter(storedData: try #require(reopened.data(forKey: "tasksFilter")))
        #expect(restored == filter)
        #expect(restored.activeCount == 4)
        reopened.set(TaskFilter().storedData, forKey: "tasksFilter")
        let reset = TaskFilter(storedData: try #require(preferences.data(forKey: "tasksFilter")))
        #expect(reset == TaskFilter())
        #expect(TaskPageQuery(filter: reset).parameters()["due"] == "any")
    }

    @Test func emptyDamagedAndUnknownPreferencesFallBackToAllTasks() {
        #expect(TaskFilter(storedData: Data()) == TaskFilter())
        #expect(TaskFilter(storedData: Data("invalid JSON".utf8)) == TaskFilter())
        #expect(TaskFilter(storedData: Data(#"{"due":"unknown"}"#.utf8)) == TaskFilter())
    }

    @Test func restoredFilterSendsRelativeDatesAndAllSelectionsToServer() {
        var filter = TaskFilter()
        filter.due = .today
        filter.priority = .high
        filter.sphere = "work"
        filter.goalID = UUID()
        let restored = TaskFilter(storedData: filter.storedData)
        let query = TaskPageQuery(filter: restored, search: "  Отчёт банк  ", status: .doing, sort: .position)
        let parameters = query.parameters(cursor: "next-page", limit: 50)
        #expect(parameters["due"] == "today")
        #expect(parameters["priority"] == "high")
        #expect(parameters["sphere"] == "work")
        #expect(parameters["goal_id"] == filter.goalID?.uuidString)
        #expect(parameters["q"] == "Отчёт банк")
        #expect(parameters["status"] == "doing")
        #expect(parameters["sort"] == "position")
        #expect(parameters["cursor"] == "next-page")
        #expect(parameters["limit"] == "50")
    }

    @Test func queryLimitsAreBoundedAndBackgroundScopesDoNotUseScreenFilters() {
        #expect(TaskPageQuery().parameters(limit: 1_000_000)["limit"] == "100")
        #expect(TaskPageQuery().parameters(limit: 0)["limit"] == "1")
        #expect(TaskPageQuery(scope: .reminders).parameters()["view"] == "reminders")
        #expect(TaskPageQuery(scope: .widgets).parameters()["q"] == nil)
        #expect(TaskPageQuery(scope: .today).parameters()["status"] == nil)
    }
}

extension TaskFilterTests {
    @Test func cacheCodingPreservesGoalIDInQuery() throws {
        var filter = TaskFilter()
        filter.goalID = UUID()
        let query = TaskPageQuery(filter: filter)
        let data = try JSONCoding.makeEncoder().encode(query)
        let cached = try JSONCoding.makeDecoder().decode(TaskPageQuery.self, from: data)
        #expect(cached.filter.goalID == filter.goalID)
        #expect(cached == query)
    }
}
