import LevelUpKit
import SwiftUI

struct TasksView: View {
    enum Mode: String {
        case list, board
    }

    @Environment(AppStore.self) private var store
    @AppStorage("tasksMode") private var mode: Mode = .list
    @AppStorage("tasksFilter") private var storedFilter = Data()
    @State private var editing: TaskItem?
    @State private var isCreating = false
    @State private var query = ""
    @State private var isFiltering = false
    @FocusState private var isSearchFocused: Bool

    private var filter: TaskFilter { TaskFilter(storedData: storedFilter) }

    private var filterBinding: Binding<TaskFilter> {
        Binding(
            get: { filter },
            set: { storedFilter = $0.storedData }
        )
    }

    private var filteredTasks: [TaskItem] {
        switch mode {
        case .list:
            store.tasks.listFeed.query == request ? store.tasks.listFeed.items : []
        case .board:
            TaskStatus.allCases.flatMap { status in
                let feed = store.tasks.boardFeed(status)
                return feed.query == boardRequest(status) ? feed.items : []
            }
        }
    }

    private var request: TaskPageQuery { TaskPageQuery(filter: filter, search: query) }
    private var requestID: String { "\(mode.rawValue):\(storedFilter.base64EncodedString()):\(query):\(store.tasks.revision)" }
    private var isLoading: Bool {
        switch mode {
        case .list: store.tasks.listFeed.query != request || store.tasks.listFeed.isLoading
        case .board: TaskStatus.allCases.contains { store.tasks.boardFeed($0).query != boardRequest($0) || store.tasks.boardFeed($0).isLoading }
        }
    }

    var body: some View {
        @Bindable var tasks = store.tasks
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                switch mode {
                case .list:
                    if filteredTasks.isEmpty && isLoading {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredTasks.isEmpty {
                        emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        TaskListView(tasks: filteredTasks, onOpen: { editing = $0 })
                            .refreshable { await tasks.listFeed.reload(request) }
                    }
                case .board:
                    TaskBoardView(filter: filter, search: query, onOpen: { editing = $0 })
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск по названию и заметке")
            .searchFocused($isSearchFocused)
            .onSubmit(of: .search) { isSearchFocused = false }
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
            .sheet(isPresented: $isFiltering) {
                TaskFilterSheet(filter: filterBinding)
            }
            .task(id: requestID) { await loadSelection() }
            .overlay(alignment: .bottom) { ErrorBanner(message: $tasks.errorMessage) }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Показано задач: \(filteredTasks.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    isFiltering = true
                    isSearchFocused = false
                } label: {
                    Label(filter.activeCount > 0 ? String(localized: "Фильтры: \(filter.activeCount)") : String(localized: "Фильтры"),
                          systemImage: filter.activeCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .font(.subheadline)
                .frame(minHeight: 44)
            }
            if filter.activeCount > 0 || !query.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(activeSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Сбросить") { resetFilters() }
                        .font(.caption)
                        .frame(minHeight: 44)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var emptyState: some View {
        if filter.activeCount == 0 && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView {
                Label("Задач пока нет", systemImage: "checklist")
            } description: {
                Text("Нажми «Записать» и надиктуй дела — или добавь задачу кнопкой «+».")
            } actions: {
                Button("Новая задача") { isCreating = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label("Задачи не найдены", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Измени поисковый запрос или сбрось фильтры.")
            } actions: {
                Button("Сбросить") { resetFilters() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func resetFilters() {
        query = ""
        storedFilter = TaskFilter().storedData
    }

    private func loadSelection() async {
        let tasks = store.tasks
        switch mode {
        case .list:
            await tasks.listFeed.reload(request, debounce: !query.isEmpty)
        case .board:
            async let todo: Void = tasks.todoFeed.reload(TaskPageQuery(filter: filter, search: query, status: .todo, sort: .position), debounce: !query.isEmpty)
            async let doing: Void = tasks.doingFeed.reload(TaskPageQuery(filter: filter, search: query, status: .doing, sort: .position), debounce: !query.isEmpty)
            async let done: Void = tasks.doneFeed.reload(TaskPageQuery(filter: filter, search: query, status: .done, sort: .position), debounce: !query.isEmpty)
            _ = await (todo, doing, done)
        }
    }

    private func boardRequest(_ status: TaskStatus) -> TaskPageQuery {
        TaskPageQuery(filter: filter, search: query, status: status, sort: .position)
    }

    private var activeSummary: String {
        let filters = filter.summary(in: store)
        let search = query.isEmpty ? "" : String(localized: "Поиск: \(query)")
        return [filters, search].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Список, сгруппированный по сроку.
struct TaskListView: View {
    let tasks: [TaskItem]
    let onOpen: (TaskItem) -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        let groups = TaskGroups(tasks: tasks)
        List {
            section("Просрочено", groups.overdue)
            section("Сегодня", groups.today)
            section("Завтра", groups.tomorrow)
            section("Позже", groups.later)
            section("Без срока", groups.someday)
            section("Готово", groups.done)
            TaskPageFooter(feed: store.tasks.listFeed)
        }
        .scrollDismissesKeyboard(.interactively)
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

struct TaskPageFooter: View {
    let feed: TaskFeed

    var body: some View {
        if feed.isLoading {
            HStack { Spacer(); ProgressView(); Spacer() }
        } else if feed.hasMore {
            Button("Загрузить ещё") { Task { await feed.loadMore() } }
                .frame(maxWidth: .infinity, minHeight: 44)
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
        done.sort { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
}
