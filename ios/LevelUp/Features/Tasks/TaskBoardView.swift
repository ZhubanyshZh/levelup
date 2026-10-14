import LevelUpKit
import SwiftUI

/// Канбан: три колонки, карточки перетаскиваются между ними.
struct TaskBoardView: View {
    let filter: TaskFilter
    let search: String
    let onOpen: (TaskItem) -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        BoardColumn(status: status, feed: store.tasks.boardFeed(status), expectedQuery: TaskPageQuery(filter: filter, search: search, status: status, sort: .position), onOpen: onOpen)
                            .frame(height: max(proxy.size.height - 24, 200))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct BoardColumn: View {
    let status: TaskStatus
    let feed: TaskFeed
    let expectedQuery: TaskPageQuery
    let onOpen: (TaskItem) -> Void
    @Environment(AppStore.self) private var store
    @State private var isTargeted = false

    var body: some View {
        let matchesQuery = feed.query == expectedQuery
        let tasks = matchesQuery ? feed.items : []
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(status.title, systemImage: status.symbol)
                    .font(.headline)
                Spacer()
                Text(verbatim: "\(tasks.count)\(feed.hasMore ? "+" : "")")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks) { task in
                        BoardCard(task: task)
                            .onTapGesture { onOpen(task) }
                            .draggable(task.id.uuidString) {
                                BoardCard(task: task).frame(width: 260)
                            }
                            .contextMenu { menu(for: task) }
                    }
                    if matchesQuery { TaskPageFooter(feed: feed) } else { ProgressView() }
                    if tasks.isEmpty && matchesQuery && !feed.isLoading {
                        Text(expectedQuery.filter.activeCount > 0 || !expectedQuery.search.isEmpty ? "Задачи не найдены" : "Перетащи сюда карточку")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(10)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isTargeted ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.fill.quaternary))
        )
        .dropDestination(for: String.self) { ids, _ in
            let dropped = ids.compactMap(UUID.init(uuidString:))
            let moving = store.tasks.tasks.filter { dropped.contains($0.id) }
            Task {
                for task in moving {
                    await store.tasks.move(task, to: status)
                }
            }
            return !moving.isEmpty
        } isTargeted: { isTargeted = $0 }
    }

    @ViewBuilder
    private func menu(for task: TaskItem) -> some View {
        ForEach(TaskStatus.allCases.filter { $0 != task.status }, id: \.self) { target in
            Button {
                Task { await store.tasks.move(task, to: target) }
            } label: {
                Label(target.title, systemImage: target.symbol)
            }
        }
        Divider()
        Button("Удалить", systemImage: "trash", role: .destructive) {
            Task { await store.tasks.delete(task) }
        }
    }
}

private struct BoardCard: View {
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
                .font(.subheadline.weight(.medium))
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            TaskMeta(task: task)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
    }
}
