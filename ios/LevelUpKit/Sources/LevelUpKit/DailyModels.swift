import Foundation

// MARK: - Дневник

public struct JournalEntry: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var entryDate: LocalDate
    public var text: String
    /// Однострочное резюме от ИИ, если запись пришла через «Записать».
    public var summary: String?
    /// 1 — очень плохо, 5 — отлично.
    public var mood: Int?
    public var energy: Int?
    public var tags: [String]
    public var captureId: UUID?
    public let createdAt: Date
    public var updatedAt: Date
}

/// Создание и полное обновление записи. Пустые настроение и энергия уходят как null.
public struct JournalInput: Encodable, Sendable {
    public var entryDate: LocalDate
    public var text: String
    public var mood: Int?
    public var energy: Int?
    public var tags: [String]

    public init(entryDate: LocalDate, text: String, mood: Int? = nil, energy: Int? = nil, tags: [String] = []) {
        self.entryDate = entryDate
        self.text = text
        self.mood = mood
        self.energy = energy
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case entryDate, text, mood, energy, tags
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entryDate, forKey: .entryDate)
        try container.encode(text, forKey: .text)
        try container.encode(mood, forKey: .mood)
        try container.encode(energy, forKey: .energy)
        try container.encode(tags, forKey: .tags)
    }
}

// MARK: - Покупки

public struct ShoppingItem: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var quantity: String?
    /// nil — основной список.
    public var listName: String?
    public var isBought: Bool
    public var boughtAt: Date?
    public var position: Double
    public let createdAt: Date
    public var updatedAt: Date
}

public struct ShoppingInput: Codable, Sendable, Hashable {
    public var name: String
    public var quantity: String?
    public var listName: String?

    public init(name: String, quantity: String? = nil, listName: String? = nil) {
        self.name = name
        self.quantity = quantity
        self.listName = listName
    }
}

/// Полное обновление позиции. Пустые количество и список уходят как null.
public struct ShoppingUpdate: Encodable, Sendable {
    public var name: String
    public var quantity: String?
    public var listName: String?
    public var isBought: Bool

    public init(_ item: ShoppingItem) {
        name = item.name
        quantity = item.quantity
        listName = item.listName
        isBought = item.isBought
    }

    private enum CodingKeys: String, CodingKey {
        case name, quantity, listName, isBought
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(listName, forKey: .listName)
        try container.encode(isBought, forKey: .isBought)
    }
}

// MARK: - Прогресс

public struct XPEvent: Codable, Sendable, Hashable {
    public var sourceType: String
    public var amount: Int
    public var title: String
    public var sphere: String?
    public var createdAt: Date
}

public struct LevelProgress: Codable, Sendable, Hashable {
    public var level: Int
    public var xpInLevel: Int
    public var xpForNextLevel: Int
    public var totalXp: Int
    public var todayXp: Int
    public var recent: [XPEvent]
    public var spheres: [Sphere]
    /// Дней подряд с опытом; один пропуск серию не рвёт.
    public var streakDays: Int
    public var quests: [Quest]
    /// Весь каталог по порядку; у неполученных achievedAt = nil.
    public var achievements: [Achievement]

    public static let initial = LevelProgress(
        level: 1, xpInLevel: 0, xpForNextLevel: 100, totalXp: 0, todayXp: 0, recent: []
    )

    public init(
        level: Int, xpInLevel: Int, xpForNextLevel: Int, totalXp: Int, todayXp: Int, recent: [XPEvent],
        spheres: [Sphere] = [], streakDays: Int = 0, quests: [Quest] = [], achievements: [Achievement] = []
    ) {
        self.level = level
        self.xpInLevel = xpInLevel
        self.xpForNextLevel = xpForNextLevel
        self.totalXp = totalXp
        self.todayXp = todayXp
        self.recent = recent
        self.spheres = spheres
        self.streakDays = streakDays
        self.quests = quests
        self.achievements = achievements
    }

    // Ответ сервера этапа 2 и кэш старой версии читаются: новых полей в них нет.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.decode(Int.self, forKey: .level)
        xpInLevel = try c.decode(Int.self, forKey: .xpInLevel)
        xpForNextLevel = try c.decode(Int.self, forKey: .xpForNextLevel)
        totalXp = try c.decode(Int.self, forKey: .totalXp)
        todayXp = try c.decode(Int.self, forKey: .todayXp)
        recent = try c.decode([XPEvent].self, forKey: .recent)
        spheres = try c.decodeIfPresent([Sphere].self, forKey: .spheres) ?? []
        streakDays = try c.decodeIfPresent(Int.self, forKey: .streakDays) ?? 0
        quests = try c.decodeIfPresent([Quest].self, forKey: .quests) ?? []
        achievements = try c.decodeIfPresent([Achievement].self, forKey: .achievements) ?? []
    }
}
