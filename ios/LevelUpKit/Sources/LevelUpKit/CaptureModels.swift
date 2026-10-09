import Foundation

/// Тип записи, распознанной ИИ. В модель приходит строкой: новый тип на сервере
/// не должен ломать старую версию приложения.
public enum CaptureItemKind: String, Sendable, CaseIterable {
    case task
    case profileFact = "profile_fact"
    case journal, shopping, expense, income, workout, goal, question, note
}

public struct BusyConflict: Codable, Sendable, Hashable {
    public var factId: UUID
    public var factText: String
    public var start: String
    public var end: String
}

public struct CaptureItem: Codable, Sendable, Identifiable, Hashable {
    /// Только для SwiftUI-списков, на сервер не уходит.
    public var id = UUID()
    public var type: String
    public var title: String
    public var details: String?
    public var dueDate: LocalDate?
    public var dueTime: String?
    public var remind: Bool
    public var priority: TaskPriority
    public var difficulty: Int?
    public var factCategory: FactCategory?
    public var schedule: Schedule?
    public var recurrence: Recurrence?
    public var mood: Int?
    public var energy: Int?
    public var tags: [String]
    public var products: [ShoppingInput]
    public var listName: String?
    public var include: Bool
    public var supported: Bool
    public var conflict: BusyConflict?

    public var kind: CaptureItemKind? { CaptureItemKind(rawValue: type) }

    private enum CodingKeys: String, CodingKey {
        case type, title, details, dueDate, dueTime, remind, priority, difficulty
        case factCategory, schedule, recurrence, mood, energy, tags, products, listName
        case include, supported, conflict
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        dueDate = try container.decodeIfPresent(LocalDate.self, forKey: .dueDate)
        dueTime = try container.decodeIfPresent(String.self, forKey: .dueTime)
        remind = try container.decodeIfPresent(Bool.self, forKey: .remind) ?? false
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .normal
        difficulty = try container.decodeIfPresent(Int.self, forKey: .difficulty)
        factCategory = try container.decodeIfPresent(FactCategory.self, forKey: .factCategory)
        schedule = try container.decodeIfPresent(Schedule.self, forKey: .schedule)
        recurrence = try container.decodeIfPresent(Recurrence.self, forKey: .recurrence)
        mood = try container.decodeIfPresent(Int.self, forKey: .mood)
        energy = try container.decodeIfPresent(Int.self, forKey: .energy)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        products = try container.decodeIfPresent([ShoppingInput].self, forKey: .products) ?? []
        listName = try container.decodeIfPresent(String.self, forKey: .listName)
        include = try container.decodeIfPresent(Bool.self, forKey: .include) ?? true
        supported = try container.decodeIfPresent(Bool.self, forKey: .supported) ?? false
        conflict = try container.decodeIfPresent(BusyConflict.self, forKey: .conflict)
    }
}

public enum CaptureStatus: String, Codable, Sendable {
    /// ИИ не разобрал (причина в errorCode) — лежит во «Входящих».
    case failed
    /// Разобрано, ждёт подтверждения.
    case parsed
    case confirmed
    /// Подтверждено, но часть записей ждёт своих модулей.
    case deferred
    case undone
}

public enum CaptureSource: String, Codable, Sendable {
    case text, voice, siri
}

public struct CreatedRef: Codable, Sendable, Hashable {
    public var type: String
    public var id: UUID
}

public struct Capture: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var text: String
    public var source: CaptureSource
    public var status: CaptureStatus
    public var errorCode: String?
    public var reply: String?
    public var provider: String?
    public var model: String?
    public var items: [CaptureItem]
    public var created: [CreatedRef]
    public let createdAt: Date
}

public struct CaptureResult: Decodable, Sendable {
    public var capture: Capture
    public var tasks: [TaskItem]
    public var facts: [ProfileFact]
    public var journal: [JournalEntry]
    public var shopping: [ShoppingItem]
    /// Опыт, полученный при сохранении (например, за дневник).
    public var xpGained: Int
}

public struct CaptureRequest: Codable, Sendable {
    public var text: String
    public var source: CaptureSource
    public var timezone: String?
    public var autosave: Bool

    public init(text: String, source: CaptureSource, timezone: String? = TimeZone.current.identifier, autosave: Bool = false) {
        self.text = text
        self.source = source
        self.timezone = timezone
        self.autosave = autosave
    }
}
