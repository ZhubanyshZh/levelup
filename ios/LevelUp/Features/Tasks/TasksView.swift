import LevelUpKit
import SwiftUI

struct TasksView: View {
    enum Mode: String {
        case list, board
    }

    @Environment(AppStore.self) private var store
    @AppStorage("tasksMode") private var mode: Mode = .list
    @State private var editing: TaskItem?
    @State private var isCreating = false

    var body: some View {
        @Bindable var tasks = store.tasks
        NavigationStack {
            Group {
                switch mode {
                case .list:
                    TaskListView(onOpen: { editing = $0 })
                        .refreshable { await tasks.load() }
                case .board:
                    TaskBoardView(onOpen: { editing = $0 })
                }
            }
            .navigationTitle("Задачи")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Вид", selection: $mode) {
                        Text("Список").tag(Mode.list)
                        Text("Доска").tag(Mode.board)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Label("Новая задача", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editing) { TaskEditorView(task: $0) }
            .sheet(isPresented: $isCreating) { TaskEditorView(task: nil) }
            .overlay(alignment: .bottom) { ErrorBanner(message: $tasks.errorMessage) }
        }
    }
}

/// Список, сгруппированный по сроку.
struct TaskListView: View {
    let onOpen: (TaskItem) -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        let groups = TaskGroups(tasks: store.tasks.tasks)
        List {
            if store.tasks.tasks.isEmpty {
                ContentUnavailableView(
                    "Задач пока нет",
                    systemImage: "checklist",
                    description: Text("Нажми «Записать» и надиктуй дела — или добавь задачу кнопкой «+».")
                )
                .listRowBackground(Color.clear)
            }
            section("Просрочено", groups.overdue)
            section("Сегодня", groups.today)
            section("Завтра", groups.tomorrow)
            section("Позже", groups.later)
            section("Без срока", groups.someday)
            section("Готово", groups.done)
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ tasks: [TaskItem]) -> some View {
        if !tasks.isEmpty {
            Section(title) {
                ForEach(tasks) { task in
                    TaskRow(task: task) {
                        Task { await store.tasks.toggleDone(task) }
                    }
                    .onTapGesture { onOpen(task) }
                    .swipeActions(edge: .trailing) {
                        Button("Удалить", systemImage: "trash", role: .destructive) {
                            Task { await store.tasks.delete(task) }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if task.status == .todo {
                            Button("В работу", systemImage: "circle.lefthalf.filled") {
                                Task { await store.tasks.move(task, to: .doing) }
                            }
                            .tint(.indigo)
                        }
                    }
                }
            }
        }
    }
}

struct TaskGroups {
    var overdue: [TaskItem] = []
    var today: [TaskItem] = []
    var tomorrow: [TaskItem] = []
    var later: [TaskItem] = []
    var someday: [TaskItem] = []
    var done: [TaskItem] = []

    init(tasks: [TaskItem]) {
        let todayDate = LocalDate.today()
        let tomorrowDate = todayDate.adding(days: 1)
        for task in tasks.sorted(by: TaskOrdering.byDue) {
            guard !task.isDone else {
                done.append(task)
                continue
            }
            switch task.dueDate {
            case nil: someday.append(task)
            case let date? where date < todayDate: overdue.append(task)
            case todayDate: today.append(task)
            case tomorrowDate: tomorrow.append(task)
            default: later.append(task)
            }
        }
        done = Array(done.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }.prefix(20))
    }
}
