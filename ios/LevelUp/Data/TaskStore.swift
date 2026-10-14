import Foundation
import LevelUpKit
import Observation

@MainActor
@Observable
final class TaskStore {
    private(set) var tasks: [TaskItem]
    private(set) var isLoading = false
    private(set) var revision = 0
    private(set) var widgetTasks: [TaskItem] = []
    private(set) var reminderTasks: [TaskItem] = []
    let listFeed: TaskFeed
    let todayFeed: TaskFeed
    let todoFeed: TaskFeed
    let doingFeed: TaskFeed
    let doneFeed: TaskFeed
    let goalFeed: TaskFeed
    var errorMessage: String?

    private let api: APIClient
    private let reminders: ReminderScheduler
    private let cache = LocalCache<[TaskItem]>(name: "task-entities")
    private let widgetCache = LocalCache<[TaskItem]>(name: "widget-tasks")
    private let reminderCache = LocalCache<[TaskItem]>(name: "reminder-tasks")
    private var loadGeneration = UUID()
    private var isReset = false
    var onUnauthorized: () -> Void = {}
    /// Любое изменение данных — например, чтобы обновить виджеты.
    var onChange: () -> Void = {}
    /// Выполнение и отмена выполнения меняют опыт.
    var onProgressChange: () -> Void = {}

    init(api: APIClient, reminders: ReminderScheduler) {
        self.api = api
        self.reminders = reminders
        tasks = cache.load() ?? []
        widgetTasks = widgetCache.load() ?? []
        reminderTasks = reminderCache.load() ?? []
        listFeed = TaskFeed(api: api, cacheURL: LocalCache<[TaskItem]>.directory.appending(path: "tasks-list.json"))
        todayFeed = TaskFeed(api: api, cacheURL: LocalCache<[TaskItem]>.directory.appending(path: "tasks-today.json"))
        todoFeed = TaskFeed(api: api, cacheURL: LocalCache<[TaskItem]>.directory.appending(path: "tasks-board-todo.json"))
        doingFeed = TaskFeed(api: api, cacheURL: LocalCache<[TaskItem]>.directory.appending(path: "tasks-board-doing.json"))
        doneFeed = TaskFeed(api: api, cacheURL: LocalCache<[TaskItem]>.directory.appending(path: "tasks-board-done.json"))
        goalFeed = TaskFeed(api: api, cacheURL: LocalCache<[TaskItem]>.directory.appending(path: "tasks-goal.json"))
        for feed in feeds {
            feed.onItems = { [weak self] in self?.merge($0) }
            feed.onError = { [weak self] in self?.report($0) }
        }
    }

    private var feeds: [TaskFeed] { [listFeed, todayFeed, todoFeed, doingFeed, doneFeed, goalFeed] }

    func boardFeed(_ status: TaskStatus) -> TaskFeed {
        switch status {
        case .todo: todoFeed
        case .doing: doingFeed
        case .done: doneFeed
        }
    }

    // MARK: Выборки

    func tasks(in status: TaskStatus) -> [TaskItem] {
        tasks.filter { $0.status == status }.sorted { $0.position < $1.position }
    }

    /// «Сегодня»: просроченное и на сегодня, плюс то, что уже в работе.
    var today: [TaskItem] {
        todayFeed.items
    }

    // MARK: Действия

    func load(refreshBrowse: Bool = true) async {
        guard !isReset else { return }
        let token = UUID()
        loadGeneration = token
        isLoading = true
        defer { if loadGeneration == token { isLoading = false } }
        do {
            async let widgets = api.taskPage(TaskPageQuery(scope: .widgets), limit: 100)
            async let reminders = api.taskPage(TaskPageQuery(scope: .reminders), limit: 100)
            async let todayLoaded: Void = todayFeed.reload(TaskPageQuery(scope: .today))
            let (widgetPage, reminderPage) = try await (widgets, reminders)
            await todayLoaded
            guard loadGeneration == token else { return }
            widgetTasks = widgetPage.items
            reminderTasks = reminderPage.items
            widgetCache.save(widgetTasks)
            reminderCache.save(reminderTasks)
            merge(widgetTasks + reminderTasks)
            self.reminders.sync(reminderTasks)
            if refreshBrowse { revision += 1 }
        } catch {
            guard loadGeneration == token else { return }
            report(error)
        }
    }

    func create(_ draft: TaskDraft) async -> Bool {
        do {
            insert([try await api.createTask(draft)])
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Задачи, созданные из записи, — сразу в список, не дожидаясь перезагрузки.
    func insert(_ created: [TaskItem]) {
        guard !created.isEmpty else { return }
        merge(created)
        invalidate()
    }

    func save(_ task: TaskItem) async {
        let previous = tasks.first { $0.id == task.id }
            ?? feeds.lazy.flatMap(\.items).first { $0.id == task.id }
            ?? task
        replace(task)
        do {
            let saved = try await api.updateTask(id: task.id, TaskUpdate(task))
            replace(saved)
            if previous.status != task.status && (previous.isDone || task.isDone) {
                onProgressChange()
            }
        } catch {
            replace(previous)
            report(error)
        }
        invalidate()
    }

    func toggleDone(_ task: TaskItem) async {
        var updated = task
        updated.status = task.isDone ? .todo : .done
        await save(updated)
    }

    /// Перенос между колонками канбана — карточка встаёт наверх колонки.
    func move(_ task: TaskItem, to status: TaskStatus) async {
        guard task.status != status else { return }
        var updated = task
        updated.status = status
        updated.position = (tasks(in: status).first?.position ?? 0) - 1
        await save(updated)
    }

    func delete(_ task: TaskItem) async {
        let previous = tasks
        for feed in feeds { feed.remove(task.id) }
        replaceAll(tasks.filter { $0.id != task.id })
        do {
            try await api.deleteTask(id: task.id)
        } catch {
            replaceAll(previous)
            report(error)
        }
        invalidate()
    }

    func reset() {
        isReset = true
        isLoading = false
        tasks = []
        widgetTasks = []
        reminderTasks = []
        loadGeneration = UUID()
        for feed in feeds { feed.reset() }
        reminders.clear()
    }

    // MARK: Внутреннее

    private func replace(_ task: TaskItem) {
        for feed in feeds { feed.update(task) }
        var all = tasks
        if let index = all.firstIndex(where: { $0.id == task.id }) {
            all[index] = task
        }
        replaceAll(all)
    }

    private func merge(_ incoming: [TaskItem]) {
        var ids = Set<UUID>()
        let unique = incoming.filter { ids.insert($0.id).inserted }
        replaceAll(unique + tasks.filter { !ids.contains($0.id) })
    }

    private func invalidate() {
        guard !isReset else { return }
        revision += 1
        Task { await load(refreshBrowse: false) }
    }

    private func replaceAll(_ newTasks: [TaskItem]) {
        tasks = newTasks
        cache.save(Array(newTasks.prefix(500)))
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

enum TaskOrdering {
    /// Сначала с ранним сроком, без срока — в конце; внутри дня — по времени, затем важные.
    static func byDue(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (l?, r?) where l != r: return l < r
        case (nil, _?): return false
        case (_?, nil): return true
        default:
            let lt = lhs.dueTime ?? "99:99", rt = rhs.dueTime ?? "99:99"
            if lt != rt { return lt < rt }
            return lhs.priority == .high && rhs.priority != .high
        }
    }
}
