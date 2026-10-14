import Foundation
import LevelUpKit
import Observation

/// Данные вошедшего пользователя. Создаётся при входе и уничтожается при выходе.
@MainActor
@Observable
final class AppStore {
    let tasks: TaskStore
    let captures: CaptureStore
    let profile: ProfileStore
    let ai: AISettingsStore
    let journal: JournalStore
    let shopping: ShoppingStore
    let progress: ProgressStore
    let finance: FinanceStore
    let workouts: WorkoutStore
    let coach: CoachStore
    let goals: GoalStore
    private let reminders = ReminderScheduler()
    private let coachReminders = CoachReminderScheduler()
    private var isRefreshing = false
    private var isReset = false
    private let api: APIClient
    private let widgets: WidgetPublisher
    /// Имя для виджетов — берётся из профиля, который знает SessionStore.
    private let displayName: () -> String?

    init(
        api: APIClient,
        widgets: WidgetPublisher,
        displayName: @escaping () -> String?,
        onUnauthorized: @escaping () -> Void
    ) {
        self.api = api
        self.widgets = widgets
        self.displayName = displayName
        tasks = TaskStore(api: api, reminders: reminders)
        captures = CaptureStore(api: api)
        profile = ProfileStore(api: api)
        ai = AISettingsStore(api: api)
        journal = JournalStore(api: api)
        shopping = ShoppingStore(api: api)
        progress = ProgressStore(api: api)
        finance = FinanceStore(api: api)
        workouts = WorkoutStore(api: api)
        goals = GoalStore(api: api)
        coach = CoachStore(api: api)

        tasks.onUnauthorized = onUnauthorized
        finance.onUnauthorized = onUnauthorized
        workouts.onUnauthorized = onUnauthorized
        goals.onUnauthorized = onUnauthorized
        coach.onUnauthorized = onUnauthorized
        captures.onUnauthorized = onUnauthorized
        profile.onUnauthorized = onUnauthorized
        ai.onUnauthorized = onUnauthorized
        journal.onUnauthorized = onUnauthorized
        shopping.onUnauthorized = onUnauthorized
        progress.onUnauthorized = onUnauthorized

        let progress = progress
        let refreshProgress: () -> Void = { _ = Task { await progress.refreshAfterAction() } }
        tasks.onProgressChange = refreshProgress
        journal.onProgressChange = refreshProgress
        workouts.onProgressChange = refreshProgress
        goals.onProgressChange = refreshProgress

        let publish: () -> Void = { [weak self] in self?.publishWidgets() }
        tasks.onChange = publish
        shopping.onChange = publish
        journal.onChange = publish
        profile.onChange = { [weak self] in
            publish()
            self?.syncCoachReminders()
        }
        finance.onChange = publish
        workouts.onChange = publish
        goals.onChange = publish
        progress.onChange = { _ in publish() }
    }

    func refreshAll() async {
        guard !isRefreshing && !isReset else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        // Сначала отметки, сделанные в виджетах без приложения, — иначе загрузка их затрёт.
        await WidgetActionSender.flush(api: api, store: widgets.pending)
        // Затем «Входящие»: сервер заодно раскладывает записи, ждавшие своих разделов.
        await captures.loadInbox()
        async let tasksLoaded: Void = tasks.load()
        async let factsLoaded: Void = profile.load()
        async let aiLoaded: Void = ai.load()
        async let journalLoaded: Void = journal.load()
        async let shoppingLoaded: Void = shopping.load()
        async let progressLoaded: Void = progress.load()
        async let financeLoaded: Void = finance.load()
        async let workoutsLoaded: Void = workouts.load()
        async let goalsLoaded: Void = goals.load()
        async let coachLoaded: Void = coach.load()
        _ = await (tasksLoaded, factsLoaded, aiLoaded, journalLoaded, shoppingLoaded, progressLoaded)
        _ = await (financeLoaded, workoutsLoaded, goalsLoaded, coachLoaded)
        await captures.flushOutbox()
        guard !isReset else { return }
        syncCoachReminders()
        if UserDefaults.standard.bool(forKey: "coachAutomatic"), ai.settings?.activeProvider != nil {
            let kind = CoachKind.current()
            if coach.report(kind) == nil { await coach.generate(kind) }
            if LocalDate.today().weekday == .mon, coach.report(.weekly) == nil { await coach.generate(.weekly) }
        }
    }

    func configureCoachReminders(_ enabled: Bool) async -> Bool {
        if enabled {
            let allowed = await coachReminders.authorize()
            if !allowed {
                coach.errorMessage = String(localized: "Разреши уведомления: Настройки → Level Up.")
                return false
            }
        }
        syncCoachReminders()
        return true
    }

    private func syncCoachReminders() {
        guard !isReset else { return }
        let enabled = UserDefaults.standard.bool(forKey: "coachReminders")
        reminders.reservedSlots = enabled ? 15 : 0
        reminders.sync(tasks.reminderTasks)
        coachReminders.sync(enabled: enabled, facts: profile.facts)
    }

    /// Применяет результат подтверждённой записи сразу, без полной перезагрузки.
    func apply(_ result: CaptureResult) {
        tasks.insert(result.tasks)
        profile.insert(result.facts)
        journal.insert(result.journal)
        shopping.insert(result.shopping)
        finance.insert(result.transactions)
        workouts.insert(result.workouts)
        goals.insert(result.goals)
        if result.xpGained > 0 {
            Task { await progress.refreshAfterAction() }
        }
    }

    /// Пересобрать снимок для виджетов (с небольшой задержкой, чтобы склеить пачку изменений).
    func publishWidgets() {
        widgets.schedule { [weak self] in self?.widgetSnapshot() ?? .signedOut }
    }

    private func widgetSnapshot() -> WidgetSnapshot {
        let today = LocalDate.today()
        var snapshot = WidgetSnapshot(
            isSignedIn: true,
            displayName: displayName(),
            tasks: WidgetSnapshot.taskEntries(tasks.widgetTasks, today: today),
            shopping: WidgetSnapshot.shoppingEntries(shopping.items),
            journalDays: WidgetSnapshot.journalDays(journal.entries, today: today),
            busy: WidgetSnapshot.busySlots(profile.facts)
        )
        snapshot.apply(progress.progress, today: today)
        snapshot.streakDays = progress.progress.streakDays
        snapshot.quests = progress.progress.quests.map { quest in
            WidgetSnapshot.QuestEntry(
                id: quest.id, title: quest.title, isDaily: quest.period == .day, periodEnd: quest.periodEnd,
                progress: quest.progress, target: quest.target, reward: quest.reward, isDone: quest.isDone
            )
        }
        if let summary = finance.summary, finance.isCurrentMonth {
            snapshot.finance = WidgetSnapshot.FinanceEntry(
                currency: summary.currency, month: finance.month, day: today,
                spentMonth: summary.spent, spentToday: summary.spentToday, monthlyBudget: summary.totalBudget?.monthlyLimit
            )
        }
        let last = workouts.workouts.first
        snapshot.workouts = WidgetSnapshot.WorkoutEntry(
            days: Array(Set(workouts.workouts.map(\.workoutDate).filter { $0 >= today.adding(days: -60) })).sorted(),
            lastTitle: last.map { $0.title ?? $0.exercises.map(\.name).prefix(2).joined(separator: ", ") },
            lastDate: last?.workoutDate,
            lastRecord: workouts.workouts.lazy.flatMap(\.sets).first(where: \.isPr)?.exercise,
            activeSince: workouts.active?.startedAt
        )
        snapshot.goals = goals.active.map { goal in
            WidgetSnapshot.GoalEntry(
                id: goal.id, title: goal.title, progress: goal.progress, deadline: goal.deadline,
                icon: progress.sphere(goal.sphere)?.icon
            )
        }
        return snapshot
    }

    func reset() {
        isReset = true
        tasks.reset()
        captures.reset()
        profile.reset()
        ai.reset()
        journal.reset()
        shopping.reset()
        progress.reset()
        finance.reset()
        workouts.reset()
        goals.reset()
        coach.reset()
        coachReminders.clear()
        UserDefaults.standard.removeObject(forKey: "coachAutomatic")
        UserDefaults.standard.removeObject(forKey: "coachReminders")
        UserDefaults.standard.removeObject(forKey: "tasksFilter")
        LocalCache<[TaskItem]>.clearAll()
    }
}
