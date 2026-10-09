import Foundation

/// Сфера жизни со своим уровнем.
public struct Sphere: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var key: String
    public var name: String
    public var icon: String
    public var position: Double
    public var isCustom: Bool
    public var level: Int
    public var xpInLevel: Int
    public var xpForNextLevel: Int
    public var totalXp: Int

    public var fraction: Double { Double(xpInLevel) / Double(max(xpForNextLevel, 1)) }
}

public struct SphereInput: Encodable, Sendable {
    public var name: String
    public var icon: String

    public init(name: String, icon: String) {
        self.name = name
        self.icon = icon
    }
}

public enum QuestKind: String, Codable, Sendable {
    case tasks, journal, workouts
    case goalSteps = "goal_steps"
    case comeback
}

public enum QuestPeriod: String, Codable, Sendable {
    case day, week
}

public struct Quest: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var period: QuestPeriod
    public var periodStart: LocalDate
    public var periodEnd: LocalDate
    /// Строкой: новый вид квеста на сервере не должен ломать старое приложение.
    public var kind: String
    public var target: Int
    public var progress: Int
    public var reward: Int
    public var sphere: String?
    public var completedAt: Date?

    public var questKind: QuestKind? { QuestKind(rawValue: kind) }
    public var isDone: Bool { completedAt != nil }
    public var fraction: Double { Double(progress) / Double(max(target, 1)) }
}

public struct Achievement: Codable, Sendable, Identifiable, Hashable {
    public var code: String
    public var achievedAt: Date?

    public var id: String { code }
    public var isUnlocked: Bool { achievedAt != nil }
}
