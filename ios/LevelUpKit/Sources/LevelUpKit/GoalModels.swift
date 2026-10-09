import Foundation

public enum GoalStatus: String, Codable, Sendable {
    case active, done
}

public struct GoalStep: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var title: String
    public var isDone: Bool
    public var doneAt: Date?
    public var position: Double
}

public struct Goal: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var title: String
    public var why: String?
    public var deadline: LocalDate?
    public var metricUnit: String?
    public var startValue: Double?
    public var currentValue: Double?
    public var targetValue: Double?
    public var sphere: String?
    public var status: GoalStatus
    public var completedAt: Date?
    public var position: Double
    public var steps: [GoalStep]
    /// 0…1: по метрике, если она есть, иначе по шагам.
    public var progress: Double
    public var captureId: UUID?
    public let createdAt: Date
    public var updatedAt: Date

    public var isDone: Bool { status == .done }
    public var hasMetric: Bool { targetValue != nil }

    /// Дней до дедлайна (отрицательное — просрочено).
    public func daysLeft(from today: LocalDate = .today()) -> Int? {
        guard let deadline else { return nil }
        return Calendar.current.dateComponents([.day], from: today.date(), to: deadline.date()).day
    }
}

/// Создание цели. Пустые поля не отправляются.
public struct GoalInput: Encodable, Sendable {
    public var title: String
    public var why: String?
    public var deadline: LocalDate?
    public var metricUnit: String?
    public var startValue: Double?
    public var currentValue: Double?
    public var targetValue: Double?
    public var sphere: String?
    public var steps: [String]

    public init(title: String, why: String? = nil, deadline: LocalDate? = nil, metricUnit: String? = nil, startValue: Double? = nil, currentValue: Double? = nil, targetValue: Double? = nil, sphere: String? = nil, steps: [String] = []) {
        self.title = title
        self.why = why
        self.deadline = deadline
        self.metricUnit = metricUnit
        self.startValue = startValue
        self.currentValue = currentValue
        self.targetValue = targetValue
        self.sphere = sphere
        self.steps = steps
    }
}

/// Полное состояние редактируемых полей цели. Пустые значения уходят как null.
public struct GoalUpdate: Encodable, Sendable {
    public var title: String
    public var why: String?
    public var deadline: LocalDate?
    public var metricUnit: String?
    public var startValue: Double?
    public var currentValue: Double?
    public var targetValue: Double?
    public var sphere: String?
    public var status: GoalStatus

    public init(_ goal: Goal) {
        title = goal.title
        why = goal.why
        deadline = goal.deadline
        metricUnit = goal.metricUnit
        startValue = goal.startValue
        currentValue = goal.currentValue
        targetValue = goal.targetValue
        sphere = goal.sphere
        status = goal.status
    }

    private enum CodingKeys: String, CodingKey {
        case title, why, deadline, metricUnit, startValue, currentValue, targetValue, sphere, status
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(why, forKey: .why)
        try container.encode(deadline, forKey: .deadline)
        try container.encode(metricUnit, forKey: .metricUnit)
        try container.encode(startValue, forKey: .startValue)
        try container.encode(currentValue, forKey: .currentValue)
        try container.encode(targetValue, forKey: .targetValue)
        try container.encode(sphere, forKey: .sphere)
        try container.encode(status, forKey: .status)
    }
}
