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

/// Упражнение в записи о тренировке: «3 подхода по 5 с 80 кг».
public struct ExerciseEntry: Codable, Sendable, Hashable {
    public var name: String
    public var sets: Int
    public var reps: Int?
    public var weightKg: Double?
    public var durationSec: Int?
    public var distanceM: Double?

    public init(name: String, sets: Int = 1, reps: Int? = nil, weightKg: Double? = nil, durationSec: Int? = nil, distanceM: Double? = nil) {
        self.name = name
        self.sets = sets
        self.reps = reps
        self.weightKg = weightKg
        self.durationSec = durationSec
        self.distanceM = distanceM
    }
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
    public var amount: Double?
    public var currency: String?
    public var category: String?
    public var exercises: [ExerciseEntry]
    public var targetValue: Double?
    public var metricUnit: String?
    public var sphere: String?
    public var include: Bool
    public var supported: Bool
    public var conflict: BusyConflict?

    public var kind: CaptureItemKind? { CaptureItemKind(rawValue: type) }

    private enum CodingKeys: String, CodingKey {
        case type, title, details, dueDate, dueTime, remind, priority, difficulty
        case factCategory, schedule, recurrence, mood, energy, tags, products, listName
        case amount, currency, category, exercises, targetValue, metricUnit, sphere
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
        amount = try container.decodeIfPresent(Double.self, forKey: .amount)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        exercises = try container.decodeIfPresent([ExerciseEntry].self, forKey: .exercises) ?? []
        targetValue = try container.decodeIfPresent(Double.self, forKey: .targetValue)
        metricUnit = try container.decodeIfPresent(String.self, forKey: .metricUnit)
        sphere = try container.decodeIfPresent(String.self, forKey: .sphere)
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
    public var transactions: [MoneyTransaction]
    public var workouts: [Workout]
    public var goals: [Goal]
    /// Опыт, полученный при сохранении (например, за дневник).
    public var xpGained: Int

    private enum CodingKeys: String, CodingKey {
        case capture, tasks, facts, journal, shopping, transactions, workouts, goals, xpGained
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        capture = try c.decode(Capture.self, forKey: .capture)
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        facts = try c.decodeIfPresent([ProfileFact].self, forKey: .facts) ?? []
        journal = try c.decodeIfPresent([JournalEntry].self, forKey: .journal) ?? []
        shopping = try c.decodeIfPresent([ShoppingItem].self, forKey: .shopping) ?? []
        transactions = try c.decodeIfPresent([MoneyTransaction].self, forKey: .transactions) ?? []
        workouts = try c.decodeIfPresent([Workout].self, forKey: .workouts) ?? []
        goals = try c.decodeIfPresent([Goal].self, forKey: .goals) ?? []
        xpGained = try c.decodeIfPresent(Int.self, forKey: .xpGained) ?? 0
    }
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
