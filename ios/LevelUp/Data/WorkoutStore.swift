import ActivityKit
import Foundation
import LevelUpKit
import Observation
@preconcurrency import UserNotifications

/// Тренировки: история, статистика упражнений и тренировка в процессе.
///
/// Тренировка в процессе живёт на телефоне (переживает перезапуск приложения) и уходит
/// на сервер целиком по «Завершить» — так зал без связи ничего не ломает.
@MainActor
@Observable
final class WorkoutStore {
    private(set) var workouts: [Workout]
    private(set) var exercises: [ExerciseStats]
    private(set) var active: ActiveWorkout?
    /// Итог только что завершённой тренировки (опыт, рекорды) — для экрана «Готово».
    var lastResult: WorkoutResult?
    var errorMessage: String?

    /// Отдых между подходами, секунд.
    var restSeconds: Int {
        didSet { UserDefaults.standard.set(restSeconds, forKey: Self.restKey) }
    }

    private let api: APIClient
    private let cache = LocalCache<[Workout]>(name: "workouts")
    private let exerciseCache = LocalCache<[ExerciseStats]>(name: "exercises")
    private let activeCache = LocalCache<ActiveWorkout>(name: "active-workout")
    private var activity: Activity<WorkoutActivityAttributes>?
    private static let restKey = "levelup.restSeconds"
    private static let restNotification = "workout-rest"
    var onUnauthorized: () -> Void = {}
    var onChange: () -> Void = {}
    var onProgressChange: () -> Void = {}

    init(api: APIClient) {
        self.api = api
        workouts = cache.load() ?? []
        exercises = exerciseCache.load() ?? []
        active = activeCache.load()
        let saved = UserDefaults.standard.integer(forKey: Self.restKey)
        restSeconds = saved > 0 ? saved : 90
        activity = Activity<WorkoutActivityAttributes>.activities.first
    }

    // MARK: Выборки

    /// Тренировки этой недели (пн–вс).
    var thisWeek: [Workout] {
        let today = LocalDate.today()
        let monday = today.adding(days: -(Weekday.allCases.firstIndex(of: today.weekday) ?? 0))
        return workouts.filter { $0.workoutDate >= monday }
    }

    /// Названия упражнений для подсказок: сначала недавние.
    var exerciseNames: [String] { exercises.map(\.name) }

    /// Последний подход упражнения — чтобы подставить вес и повторы.
    func lastSet(of exercise: String) -> SetInput? {
        let key = exercise.lowercased().trimmingCharacters(in: .whitespaces)
        if let current = active?.sets.last(where: { $0.exercise.lowercased() == key }) {
            return current
        }
        for workout in workouts {
            if let set = workout.sets.last(where: { $0.exercise.lowercased() == key }) {
                return SetInput(exercise: set.exercise, weightKg: set.weightKg, reps: set.reps, durationSec: set.durationSec, distanceM: set.distanceM)
            }
        }
        return nil
    }

    // MARK: Загрузка

    func load() async {
        do {
            async let list = api.workouts()
            async let stats = api.exerciseStats()
            let (loadedWorkouts, loadedStats) = try await (list, stats)
            workouts = loadedWorkouts
            exercises = loadedStats
            cache.save(loadedWorkouts)
            exerciseCache.save(loadedStats)
            onChange()
        } catch {
            report(error)
        }
    }

    func insert(_ created: [Workout]) {
        guard !created.isEmpty else { return }
        workouts = created + workouts.filter { workout in !created.contains { $0.id == workout.id } }
        cache.save(workouts)
        onChange()
        Task { await load() }
    }

    func delete(_ workout: Workout) async {
        workouts.removeAll { $0.id == workout.id }
        do {
            try await api.deleteWorkout(id: workout.id)
            onProgressChange()
        } catch {
            report(error)
        }
        await load()
    }

    func save(_ input: WorkoutInput, editing workout: Workout) async -> Bool {
        do {
            let result = try await api.updateWorkout(id: workout.id, input)
            workouts = workouts.map { $0.id == workout.id ? result.workout : $0 }
            cache.save(workouts)
            onChange()
            onProgressChange()
            await load()
            return true
        } catch {
            report(error)
            return false
        }
    }

    // MARK: Тренировка в процессе

    func start(title: String? = nil) {
        guard active == nil else { return }
        setActive(ActiveWorkout(title: title))
        startActivity()
    }

    func select(exercise: String) {
        guard var workout = active else { return }
        workout.currentExercise = exercise.trimmingCharacters(in: .whitespacesAndNewlines)
        setActive(workout)
        updateActivity()
    }

    /// Записать подход и начать отдых.
    func add(_ set: SetInput) {
        guard var workout = active, set.hasMeasure, !set.exercise.isEmpty else { return }
        workout.sets.append(set)
        workout.currentExercise = set.exercise
        workout.restEndsAt = restSeconds > 0 ? Date.now.addingTimeInterval(TimeInterval(restSeconds)) : nil
        setActive(workout)
        updateActivity()
        scheduleRestNotification(at: workout.restEndsAt)
    }

    func removeSet(at index: Int) {
        guard var workout = active, workout.sets.indices.contains(index) else { return }
        workout.sets.remove(at: index)
        setActive(workout)
        updateActivity()
    }

    func extendRest(by seconds: TimeInterval) {
        guard var workout = active else { return }
        let base = max(workout.restEndsAt ?? .now, .now)
        workout.restEndsAt = base.addingTimeInterval(seconds)
        setActive(workout)
        updateActivity()
        scheduleRestNotification(at: workout.restEndsAt)
    }

    func skipRest() {
        guard var workout = active else { return }
        workout.restEndsAt = nil
        setActive(workout)
        updateActivity()
        scheduleRestNotification(at: nil)
    }

    /// Отправить тренировку на сервер. Без подходов — просто закрыть.
    func finish(note: String? = nil) async -> Bool {
        guard let workout = active else { return false }
        guard !workout.sets.isEmpty else {
            cancel()
            return true
        }
        let input = WorkoutInput(
            workoutDate: LocalDate(workout.startedAt),
            startedAt: workout.startedAt,
            endedAt: .now,
            title: workout.title,
            note: note,
            sets: workout.sets
        )
        do {
            let result = try await api.createWorkout(input)
            lastResult = result
            clearActive()
            insert([result.workout])
            onProgressChange()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func cancel() {
        clearActive()
    }

    func reset() {
        workouts = []
        exercises = []
        clearActive()
    }

    // MARK: Внутреннее

    private func setActive(_ workout: ActiveWorkout) {
        let started = active == nil
        active = workout
        activeCache.save(workout)
        if started { onChange() }
    }

    private func clearActive() {
        let wasActive = active != nil
        active = nil
        activeCache.clear()
        if wasActive { onChange() }
        scheduleRestNotification(at: nil)
        endActivity()
    }

    private var activityState: WorkoutActivityAttributes.ContentState {
        let sets = active?.sets ?? []
        return WorkoutActivityAttributes.ContentState(
            exercise: active?.currentExercise ?? sets.last?.exercise,
            setCount: sets.count,
            lastSet: sets.last.map(WorkoutFormat.set),
            restEndsAt: active?.restEndsAt
        )
    }

    private func startActivity() {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled, let active else { return }
        let attributes = WorkoutActivityAttributes(
            startedAt: active.startedAt,
            title: active.title ?? String(localized: "Тренировка")
        )
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: activityState, staleDate: nil)
        )
    }

    private func updateActivity() {
        guard let activity else {
            startActivity()
            return
        }
        let content = ActivityContent(state: activityState, staleDate: active?.restEndsAt)
        Task { await activity.update(content) }
    }

    private func endActivity() {
        let current = activity
        activity = nil
        Task {
            for running in Activity<WorkoutActivityAttributes>.activities {
                await running.end(nil, dismissalPolicy: .immediate)
            }
            _ = current
        }
    }

    /// «Отдых окончен» — уведомлением, если телефон в кармане.
    private func scheduleRestNotification(at date: Date?) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.restNotification])
        guard let date, date > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Отдых окончен")
        content.body = active?.currentExercise.map { String(localized: "Следующий подход: \($0)") } ?? ""
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: date.timeIntervalSinceNow, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.restNotification, content: content, trigger: trigger))
    }

    private func report(_ error: Error) {
        if (error as? APIError)?.isUnauthorized == true {
            onUnauthorized()
        } else {
            errorMessage = ErrorText.message(for: error)
        }
    }
}
