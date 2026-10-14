import Foundation
import Observation

/// Одна серверная выборка со своим курсором. Колонки канбана не делят страницу.
@MainActor
@Observable
public final class TaskFeed {
    public private(set) var items: [TaskItem] = []
    public private(set) var nextCursor: String?
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    public private(set) var query: TaskPageQuery?
    public var hasMore: Bool { nextCursor != nil }
    public var onItems: ([TaskItem]) -> Void = { _ in }
    public var onError: (Error) -> Void = { _ in }

    private let api: APIClient
    private let cache: AppGroupFile<Snapshot>?
    private var generation = UUID()

    private struct Snapshot: Codable, Sendable {
        let query: TaskPageQuery
        let items: [TaskItem]
        let nextCursor: String?
    }

    public init(api: APIClient, cacheURL: URL? = nil) {
        self.api = api
        cache = cacheURL.map { AppGroupFile(directory: $0.deletingLastPathComponent(), name: $0.lastPathComponent) }
        if let saved = cache?.read() {
            query = saved.query
            items = saved.items
            nextCursor = saved.nextCursor
            hasLoaded = true
        }
    }

    public func reload(_ query: TaskPageQuery, debounce: Bool = false) async {
        let token = UUID()
        generation = token
        if self.query != query {
            items = []
            nextCursor = nil
            hasLoaded = false
        }
        self.query = query
        isLoading = true
        defer { if generation == token { isLoading = false } }
        do {
            if debounce { try await Task.sleep(for: .milliseconds(300)) }
            try Task.checkCancellation()
            let page = try await api.taskPage(query)
            guard generation == token, !Task.isCancelled else { return }
            items = page.items
            nextCursor = page.nextCursor
            hasLoaded = true
            cache?.write(Snapshot(query: query, items: items, nextCursor: nextCursor))
            onItems(items)
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            onError(error)
        }
    }

    public func loadMore() async {
        guard !isLoading, let query, let nextCursor else { return }
        let token = generation
        isLoading = true
        defer { if generation == token { isLoading = false } }
        do {
            let page = try await api.taskPage(query, cursor: nextCursor)
            guard generation == token, !Task.isCancelled else { return }
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            self.nextCursor = page.nextCursor
            onItems(page.items)
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            if case APIError.server(_, "invalid_task_cursor") = error {
                await reload(query)
                return
            }
            onError(error)
        }
    }

    public func update(_ task: TaskItem) {
        if let index = items.firstIndex(where: { $0.id == task.id }) { items[index] = task }
    }

    public func remove(_ id: UUID) { items.removeAll { $0.id == id } }

    public func reset() {
        cache?.delete()
        generation = UUID()
        items = []
        nextCursor = nil
        query = nil
        hasLoaded = false
        isLoading = false
    }
}
