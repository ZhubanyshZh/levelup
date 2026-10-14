import Foundation

/// Общая выборка для списка и доски; календарные границы можно задать в тестах.
public struct TaskFilter: Codable, Equatable, Sendable {
    public enum Due: String, Codable, CaseIterable, Sendable {
        case any, overdue, today, tomorrow, nextSevenDays, noDate
    }

    public var due: Due = .any
    public var priority: TaskPriority?
    public var sphere: String?
    public var goalID: UUID?

    public init() {}

    private enum CodingKeys: String, CodingKey { case due, priority, sphere, goalID, goalId }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        due = try container.decodeIfPresent(Due.self, forKey: .due) ?? .any
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority)
        sphere = try container.decodeIfPresent(String.self, forKey: .sphere)
        goalID = try container.decodeIfPresent(UUID.self, forKey: .goalID)
            ?? container.decodeIfPresent(UUID.self, forKey: .goalId)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(due, forKey: .due)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(sphere, forKey: .sphere)
        try container.encodeIfPresent(goalID, forKey: .goalID)
    }

    /// Пустые или повреждённые настройки открывают полную выборку.
    public init(storedData: Data) {
        self = (try? JSONDecoder().decode(Self.self, from: storedData)) ?? Self()
    }

    public var storedData: Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    public var activeCount: Int {
        (due == .any ? 0 : 1)
            + (priority == nil ? 0 : 1) + (sphere == nil ? 0 : 1) + (goalID == nil ? 0 : 1)
    }

}
