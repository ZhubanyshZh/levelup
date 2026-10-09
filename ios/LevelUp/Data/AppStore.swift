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

    init(api: APIClient, onUnauthorized: @escaping () -> Void, onProgress: @escaping (LevelProgress) -> Void) {
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
        progress.onChange = onProgress

        let progress = progress
        tasks.onProgressChange = { _ = Task { await progress.refreshAfterAction() } }
        journal.onProgressChange = { _ = Task { await progress.refreshAfterAction() } }
    }

    func refreshAll() async {
        // Сначала «Входящие»: сервер заодно раскладывает записи, ждавшие своих разделов.
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
