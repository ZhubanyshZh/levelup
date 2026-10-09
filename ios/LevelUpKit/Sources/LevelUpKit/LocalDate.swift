import Foundation

/// Дата без времени и часового пояса («2026-10-10»). Срок задачи — именно такой:
/// «завтра» не должно превращаться во «вчера» при смене часового пояса.
public struct LocalDate: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    public init?(string: String) {
        let parts = string.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public static func today(calendar: Calendar = .current) -> LocalDate {
        LocalDate(.now, calendar: calendar)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Начало этого дня в календаре (по умолчанию — текущий часовой пояс устройства).
    public func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    public func adding(days: Int, calendar: Calendar = .current) -> LocalDate {
        LocalDate(calendar.date(byAdding: .day, value: days, to: date(calendar: calendar)) ?? .now, calendar: calendar)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = LocalDate(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(raw)")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
