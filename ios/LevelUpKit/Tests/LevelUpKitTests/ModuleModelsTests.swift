import Foundation
import Testing
@testable import LevelUpKit

struct ModuleModelsTests {
    private let decoder = JSONCoding.makeDecoder()

    @Test func progressDecodesSpheresQuestsAndAchievements() throws {
        let json = Data("""
        {"level":3,"xp_in_level":40,"xp_for_next_level":520,"total_xp":423,"today_xp":25,
         "recent":[{"source_type":"workout","amount":25,"title":"Жим","sphere":"body","created_at":"2026-10-10T08:00:00Z"}],
         "spheres":[{"id":"6f1c2a8e-9a51-4c3b-8f0a-3c3e2b1d4a5f","key":"body","name":"Тело","icon":"💪","position":0,
                     "is_custom":false,"level":1,"xp_in_level":25,"xp_for_next_level":100,"total_xp":25}],
         "streak_days":4,
         "quests":[{"id":"9b2b1d7c-6a0e-4a43-9a52-0f3c7c1f6f10","period":"week","period_start":"2026-10-05",
                    "period_end":"2026-10-11","kind":"workouts","target":3,"progress":1,"reward":150,
                    "sphere":"body","completed_at":null}],
         "achievements":[{"code":"first_task","achieved_at":"2026-10-09T10:00:00Z"},{"code":"first_pr","achieved_at":null}]}
        """.utf8)

        let progress = try decoder.decode(LevelProgress.self, from: json)

        #expect(progress.spheres.first?.fraction == 0.25)
        #expect(progress.streakDays == 4)
        #expect(progress.quests.first?.questKind == .workouts)
        #expect(progress.quests.first?.periodEnd == LocalDate(year: 2026, month: 10, day: 11))
        #expect(progress.achievements.map(\.isUnlocked) == [true, false])
        #expect(progress.recent.first?.sphere == "body")
    }

    @Test func progressFromOlderServerStillDecodes() throws {
        let json = Data(#"{"level":1,"xp_in_level":10,"xp_for_next_level":100,"total_xp":10,"today_xp":10,"recent":[]}"#.utf8)

        let progress = try decoder.decode(LevelProgress.self, from: json)

        #expect(progress.quests.isEmpty)
        #expect(progress.streakDays == 0)
    }

    @Test func workoutGroupsSetsByExercise() throws {
        let json = Data("""
        {"id":"9b2b1d7c-6a0e-4a43-9a52-0f3c7c1f6f10","workout_date":"2026-10-10","started_at":null,"ended_at":null,
         "title":null,"note":null,"capture_id":null,"created_at":"2026-10-10T08:00:00Z","updated_at":"2026-10-10T08:00:00Z",
         "sets":[
          {"id":"6f1c2a8e-9a51-4c3b-8f0a-3c3e2b1d4a51","exercise":"Жим лёжа","weight_kg":80,"reps":5,"duration_sec":null,"distance_m":null,"is_pr":false},
          {"id":"6f1c2a8e-9a51-4c3b-8f0a-3c3e2b1d4a52","exercise":"Присед","weight_kg":100,"reps":5,"duration_sec":null,"distance_m":null,"is_pr":true},
          {"id":"6f1c2a8e-9a51-4c3b-8f0a-3c3e2b1d4a53","exercise":"Жим лёжа","weight_kg":82.5,"reps":3,"duration_sec":null,"distance_m":null,"is_pr":false}]}
        """.utf8)

        let workout = try decoder.decode(Workout.self, from: json)

        #expect(workout.exercises.map(\.name) == ["Жим лёжа", "Присед"])
        #expect(workout.exercises[0].sets.count == 2)
        #expect(workout.hasRecord)
    }

    @Test func workoutUpdateSendsNullsToClearFields() throws {
        let input = WorkoutInput(
            workoutDate: LocalDate(year: 2026, month: 10, day: 10),
            sets: [SetInput(exercise: "Жим", weightKg: 80, reps: 5)]
        )
        let body = try #require(
            JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(input)) as? [String: Any]
        )

        #expect(body["title"] is NSNull)
        #expect(body["note"] is NSNull)
        #expect(body["workout_date"] as? String == "2026-10-10")
        #expect(body["started_at"] == nil)
    }

    @Test func goalUpdateSendsNullsToClearFields() throws {
        let json = Data("""
        {"id":"9b2b1d7c-6a0e-4a43-9a52-0f3c7c1f6f10","title":"10 км","why":null,"deadline":"2026-12-01",
         "metric_unit":"км","start_value":0,"current_value":3,"target_value":10,"sphere":"body","status":"active",
         "completed_at":null,"position":0,"steps":[],"progress":0.3,"capture_id":null,
         "created_at":"2026-10-10T08:00:00Z","updated_at":"2026-10-10T08:00:00Z"}
        """.utf8)
        var goal = try decoder.decode(Goal.self, from: json)
        goal.deadline = nil

        let body = try #require(
            JSONSerialization.jsonObject(with: JSONCoding.makeEncoder().encode(GoalUpdate(goal))) as? [String: Any]
        )

        #expect(body["deadline"] is NSNull)
        #expect(body["current_value"] as? Double == 3)
        #expect(goal.daysLeft(from: LocalDate(year: 2026, month: 11, day: 30)) == nil)
    }

    @Test func captureResultWithoutNewSectionsDecodes() throws {
        let json = Data("""
        {"capture":{"id":"9b2b1d7c-6a0e-4a43-9a52-0f3c7c1f6f10","text":"x","source":"text","status":"confirmed",
         "error_code":null,"reply":null,"provider":null,"model":null,"items":[],"created":[],
         "created_at":"2026-10-10T08:00:00Z"},"tasks":[],"facts":[],"journal":[],"shopping":[],"xp_gained":0}
        """.utf8)

        let result = try decoder.decode(CaptureResult.self, from: json)

        #expect(result.transactions.isEmpty)
        #expect(result.workouts.isEmpty)
    }

    @Test func moneyCategoriesKnowTheirKind() {
        #expect(MoneyCategory.salary.kind == .income)
        #expect(MoneyCategory.cafe.kind == .expense)
        #expect(MoneyCategory.expenses.count + MoneyCategory.incomes.count == MoneyCategory.allCases.count)
    }
}
