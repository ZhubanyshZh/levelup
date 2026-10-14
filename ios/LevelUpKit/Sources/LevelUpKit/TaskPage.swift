import Foundation

public struct TaskPage: Codable, Sendable {
    public var items: [TaskItem]
    public var nextCursor: String?
    public var hasMore: Bool { nextCursor != nil }
}

/// Параметры серверной выборки. UI не отбирает задачи из общей базы на телефоне.
public struct TaskPageQuery: Codable, Equatable, Sendable {
    public enum Scope: String, Codable, Sendable { case all, today, widgets, reminders }
    public enum Sort: String, Codable, Sendable { case due, position }

    public var filter: TaskFilter
    public var search: String
    public var scope: Scope
    public var status: TaskStatus?
    public var sort: Sort

    public init(filter: TaskFilter = TaskFilter(), search: String = "", scope: Scope = .all,
                status: TaskStatus? = nil, sort: Sort = .due) {
        self.filter = filter
        self.search = search
        self.scope = scope
        self.status = status
        self.sort = sort
    }

    public func parameters(cursor: String? = nil, limit: Int = 50) -> [String: String] {
        var values = ["due": filter.due.rawValue, "view": scope.rawValue,
                      "sort": sort.rawValue, "limit": String(min(max(limit, 1), 100))]
        if let priority = filter.priority { values["priority"] = priority.rawValue }
        if let sphere = filter.sphere { values["sphere"] = sphere }
        if let goalID = filter.goalID { values["goal_id"] = goalID.uuidString }
        if let status { values["status"] = status.rawValue }
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { values["q"] = trimmed }
        if let cursor { values["cursor"] = cursor }
        return values
    }
}
