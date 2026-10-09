import Foundation

public enum Weekday: String, Codable, Sendable, CaseIterable, Comparable {
    case mon = "MON", tue = "TUE", wed = "WED", thu = "THU", fri = "FRI", sat = "SAT", sun = "SUN"

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

public enum FactCategory: String, Codable, Sendable, CaseIterable {
    case schedule, preference, health, finance, focus, personal
}

/// Регулярное время: дни недели и интервал «HH:MM». Если end < start — через полночь.
public struct Schedule: Codable, Sendable, Hashable {
    public var weekdays: [Weekday]
    public var start: String
    public var end: String
    public var busy: Bool

    public init(weekdays: [Weekday], start: String, end: String, busy: Bool = true) {
        self.weekdays = weekdays
        self.start = start
        self.end = end
        self.busy = busy
    }
}

public struct ProfileFact: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var category: FactCategory
    public var text: String
    public var schedule: Schedule?
    public var isActive: Bool
    public let createdAt: Date
    public var updatedAt: Date
}

/// Создание и полное обновление факта. schedule = nil уходит как null (убрать расписание).
public struct FactInput: Encodable, Sendable {
    public var category: FactCategory
    public var text: String
    public var schedule: Schedule?
    public var isActive: Bool

    public init(category: FactCategory, text: String, schedule: Schedule? = nil, isActive: Bool = true) {
        self.category = category
        self.text = text
        self.schedule = schedule
        self.isActive = isActive
    }

    public init(_ fact: ProfileFact) {
        self.init(category: fact.category, text: fact.text, schedule: fact.schedule, isActive: fact.isActive)
    }

    private enum CodingKeys: String, CodingKey {
        case category, text, schedule, isActive
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(category, forKey: .category)
        try container.encode(text, forKey: .text)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(isActive, forKey: .isActive)
    }
}
