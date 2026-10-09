import Foundation
import LevelUpKit
import Observation

@MainActor
@Observable
final class GoalStore {
    private(set) var goals: [Goal]
    var errorMessage: String?

    private let api: APIClient
    private let cache = LocalCache<[Goal]>(name: "goals")
    var onUnauthorized: () -> Void = {}
    var onChange: () -> Void = {}
    /// Шаги и достижение цели приносят опыт.
    var onProgressChange: () -> Void = {}

    init(api: APIClient) {
        self.api = api
        goals = cache.load() ?? []
    }

    var active: [Goal] { goals.filter { !$0.isDone } }
    var done: [Goal] { goals.filter(\.isDone) }

    func goal(_ id: UUID?) -> Goal? {
        id.flatMap { id in goals.first { $0.id == id } }
    }

    func load() async {
        do {
            replaceAll(try await api.goals())
        } catch {
            report(error)
        }
    }

    func create(_ input: GoalInput) async -> Goal? {
        do {
            let goal = try await api.createGoal(input)
            replace(goal)
            return goal
        } catch {
            report(error)
            return nil
        }
    }

    func save(_ goal: Goal) async -> Bool {
        let wasDone = self.goal(goal.id)?.isDone
        do {
            replace(try await api.updateGoal(id: goal.id, GoalUpdate(goal)))
            if wasDone != goal.isDone { onProgressChange() }
            return true
        } catch {
            report(error)
            return false
        }
    }

    func delete(_ goal: Goal) async {
        replaceAll(goals.filter { $0.id != goal.id })
        do {
            try await api.deleteGoal(id: goal.id)
        } catch {
            report(error)
            await load()
        }
    }

    func addStep(to goal: Goal, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            replace(try await api.addGoalStep(goalID: goal.id, title: trimmed))
        } catch {
            report(error)
        }
    }

    func toggle(_ step: GoalStep, in goal: Goal) async {
        // Сразу на экране, сервер догонит.
        var optimistic = goal
        if let index = optimistic.steps.firstIndex(where: { $0.id == step.id }) {
            optimistic.steps[index].isDone.toggle()
            replace(optimistic)
        }
        do {
            replace(try await api.setGoalStep(goalID: goal.id, stepID: step.id, isDone: !step.isDone))
            onProgressChange()
        } catch {
            replace(goal)
            report(error)
        }
    }

    func deleteStep(_ step: GoalStep, in goal: Goal) async {
        do {
            replace(try await api.deleteGoalStep(goalID: goal.id, stepID: step.id))
            if step.isDone { onProgressChange() }
        } catch {
            report(error)
        }
    }

    func insert(_ created: [Goal]) {
        for goal in created { replace(goal) }
    }

    func reset() {
        goals = []
    }

    private func replace(_ goal: Goal) {
        var all = goals
        if let index = all.firstIndex(where: { $0.id == goal.id }) {
            all[index] = goal
        } else {
            all.append(goal)
        }
        replaceAll(all)
    }

    private func replaceAll(_ newGoals: [Goal]) {
        goals = newGoals
        cache.save(newGoals)
        onChange()
    }

    private func report(_ error: Error) {
        if (error as? APIError)?.isUnauthorized == true {
            onUnauthorized()
        } else {
            errorMessage = ErrorText.message(for: error)
        }
    }
}
