import Foundation
import LevelUpKit
import Observation

@MainActor
@Observable
final class TaskStore {
    private(set) var tasks: [TaskItem]
    private(set) var isLoading = false
    var errorMessage: String?

    private let api: APIClient
    private let reminders: ReminderScheduler
    private let cache = LocalCache<[TaskItem]>(name: "tasks")
    var onUnauthorized: () -> Void = {}
    /// Любое изменение данных — например, чтобы обновить виджеты.
    var onChange: () -> Void = {}
    /// Выполнение и отмена выполнения меняют опыт.
    var onProgressChange: () -> Void = {}

    init(api: APIClient, reminders: ReminderScheduler) {
        self.api = api
        self.reminders = reminders
        tasks = cache.load() ?? []
    }

    // MARK: Выборки

    func tasks(in status: TaskStatus) -> [TaskItem] {
        tasks.filter { $0.status == status }.sorted { $0.position < $1.position }
    }

    /// «Сегодня»: просроченное и на сегодня, плюс то, что уже в работе.
    var today: [TaskItem] {
        let today = LocalDate.today()
        return tasks
            .filter { !$0.isDone && (($0.dueDate.map { $0 <= today }) ?? ($0.status == .doing)) }
            .sorted(by: TaskOrdering.byDue)
    }

    // MARK: Действия

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            replaceAll(try await api.tasks())
        } catch {
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
        replaceAll(created + tasks.filter { task in !created.contains { $0.id == task.id } })
    }

    func save(_ task: TaskItem) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let previous = tasks[index]
        tasks[index] = task  // сразу на экране, сервер догонит
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
        replaceAll(tasks.filter { $0.id != task.id })
        do {
            try await api.deleteTask(id: task.id)
        } catch {
            replaceAll(previous)
            report(error)
        }
    }

    func reset() {
        tasks = []
        reminders.clear()
    }

    // MARK: Внутреннее

    private func replace(_ task: TaskItem) {
        var all = tasks
        if let index = all.firstIndex(where: { $0.id == task.id }) {
            all[index] = task
        }
        replaceAll(all)
    }

    private func replaceAll(_ newTasks: [TaskItem]) {
        tasks = newTasks
        cache.save(newTasks)
        reminders.sync(newTasks)
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
