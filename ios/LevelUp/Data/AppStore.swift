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
    private let reminders = ReminderScheduler()
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

        tasks.onUnauthorized = onUnauthorized
        captures.onUnauthorized = onUnauthorized
        profile.onUnauthorized = onUnauthorized
        ai.onUnauthorized = onUnauthorized
        journal.onUnauthorized = onUnauthorized
        shopping.onUnauthorized = onUnauthorized
        progress.onUnauthorized = onUnauthorized

        let progress = progress
        tasks.onProgressChange = { _ = Task { await progress.refreshAfterAction() } }
        journal.onProgressChange = { _ = Task { await progress.refreshAfterAction() } }

        let publish: () -> Void = { [weak self] in self?.publishWidgets() }
        tasks.onChange = publish
        shopping.onChange = publish
        journal.onChange = publish
        profile.onChange = publish
        progress.onChange = { _ in publish() }
    }

    func refreshAll() async {
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
        _ = await (tasksLoaded, factsLoaded, aiLoaded, journalLoaded, shoppingLoaded, progressLoaded)
        await captures.flushOutbox()
    }

    /// Применяет результат подтверждённой записи сразу, без полной перезагрузки.
    func apply(_ result: CaptureResult) {
        tasks.insert(result.tasks)
        profile.insert(result.facts)
        journal.insert(result.journal)
        shopping.insert(result.shopping)
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
            tasks: WidgetSnapshot.taskEntries(tasks.tasks, today: today),
            shopping: WidgetSnapshot.shoppingEntries(shopping.items),
            journalDays: WidgetSnapshot.journalDays(journal.entries, today: today),
            busy: WidgetSnapshot.busySlots(profile.facts)
        )
        snapshot.apply(progress.progress, today: today)
        return snapshot
    }

    func reset() {
        tasks.reset()
        captures.reset()
        profile.reset()
        ai.reset()
        journal.reset()
        shopping.reset()
        progress.reset()
        LocalCache<[TaskItem]>.clearAll()
    }
}
