import Foundation

public enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case todo, doing, done
}

public enum TaskPriority: String, Codable, Sendable, CaseIterable {
    case low, normal, high
}

/// Повтор задачи. У повторяющейся задачи dueDate — ближайший раз; после выполнения
/// сервер сам переносит её на следующий.
public struct Recurrence: Codable, Sendable, Hashable {
    public enum Frequency: String, Codable, Sendable, CaseIterable {
        case daily, weekly, monthly
    }

    public var freq: Frequency
    public var weekdays: [Weekday]
    public var monthday: Int?

    public init(freq: Frequency, weekdays: [Weekday] = [], monthday: Int? = nil) {
        self.freq = freq
        self.weekdays = weekdays
        self.monthday = monthday
    }
}

public struct TaskItem: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var title: String
    public var notes: String?
    public var status: TaskStatus
    public var priority: TaskPriority
    public var dueDate: LocalDate?
    /// «HH:MM» в часовом поясе пользователя.
    public var dueTime: String?
    public var remind: Bool
    public var remindAt: Date?
    /// Напоминания на неделю вперёд (с учётом повторов и занятого времени) — по ним
    /// телефон ставит локальные уведомления.
    public var reminders: [Date]
    public var recurrence: Recurrence?
    public var difficulty: Int?
    /// Сфера жизни, в которую идёт опыт за задачу.
    public var sphere: String?
    public var goalId: UUID?
    public var position: Double
    public var completedAt: Date?
    public var captureId: UUID?
    public let createdAt: Date
    public var updatedAt: Date

    public var isDone: Bool { status == .done }
}

/// Новая задача. Пустые поля не отправляются — сервер подставит значения по умолчанию.
public struct TaskDraft: Encodable, Sendable {
    public var title: String
    public var notes: String?
    public var status: TaskStatus
    public var priority: TaskPriority
    public var dueDate: LocalDate?
    public var dueTime: String?
    public var remind: Bool
    public var difficulty: Int?
    public var recurrence: Recurrence?
    public var sphere: String?
    public var goalId: UUID?

    public init(
        title: String,
        notes: String? = nil,
        status: TaskStatus = .todo,
        priority: TaskPriority = .normal,
        dueDate: LocalDate? = nil,
        dueTime: String? = nil,
        remind: Bool = false,
        difficulty: Int? = nil,
        recurrence: Recurrence? = nil,
        sphere: String? = nil,
        goalId: UUID? = nil
    ) {
        self.title = title
        self.notes = notes
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.remind = remind
        self.difficulty = difficulty
        self.recurrence = recurrence
        self.sphere = sphere
        self.goalId = goalId
    }
}

/// Полное состояние редактируемых полей. Пустые значения уходят как null —
/// так сервер понимает, что срок или заметку нужно очистить.
public struct TaskUpdate: Encodable, Sendable {
    public var title: String
    public var notes: String?
    public var status: TaskStatus
    public var priority: TaskPriority
    public var dueDate: LocalDate?
    public var dueTime: String?
    public var remind: Bool
    public var difficulty: Int?
    public var recurrence: Recurrence?
    public var sphere: String?
    public var goalId: UUID?
    public var position: Double

    public init(_ task: TaskItem) {
        title = task.title
        notes = task.notes
        status = task.status
        priority = task.priority
        dueDate = task.dueDate
        dueTime = task.dueTime
        remind = task.remind
        difficulty = task.difficulty
        recurrence = task.recurrence
        sphere = task.sphere
        goalId = task.goalId
        position = task.position
    }

    private enum CodingKeys: String, CodingKey {
        case title, notes, status, priority, dueDate, dueTime, remind, difficulty, recurrence, sphere, goalId, position
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(status, forKey: .status)
        try container.encode(priority, forKey: .priority)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(dueTime, forKey: .dueTime)
        try container.encode(remind, forKey: .remind)
        try container.encode(difficulty, forKey: .difficulty)
        try container.encode(recurrence, forKey: .recurrence)
        try container.encode(sphere, forKey: .sphere)
        try container.encode(goalId, forKey: .goalId)
        try container.encode(position, forKey: .position)
    }
}
