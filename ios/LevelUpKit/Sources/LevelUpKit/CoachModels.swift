import Foundation

public enum CoachKind: String, Codable, Sendable, CaseIterable {
    case morning, evening, weekly, goal

    public static func current(at now: Date = .now, calendar: Calendar = .current) -> Self {
        calendar.component(.hour, from: now) >= 18 ? .evening : .morning
    }

    public func period(at now: Date = .now, calendar: Calendar = .current) -> LocalDate {
        let today = LocalDate(now, calendar: calendar)
        guard self == .weekly else { return today }
        let sinceMonday = (calendar.component(.weekday, from: now) + 5) % 7
        return today.adding(days: -sinceMonday - 7, calendar: calendar)
    }
}

public struct CoachAction: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var title: String
    public var notes: String?
    public var dueDate: LocalDate?
    public var dueTime: String?
    public var durationMinutes: Int
    public var difficulty: Int
    public var sphere: String?
    public var taskId: UUID?
    public var conflict: BusyConflict?
    public var appliedId: UUID?
}

public struct CoachReport: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var kind: CoachKind
    public var periodStart: LocalDate
    public var goalId: UUID?
    public var title: String
    public var message: String
    public var highlights: [String]
    public var reflectionQuestion: String?
    public var actions: [CoachAction]
    public var createdAt: Date
}

public struct CoachAppliedAction: Decodable, Sendable {
    public var report: CoachReport
    public var task: TaskItem?
    public var goal: Goal?
}

public enum CoachMetric: String, Codable, Sendable {
    case expense, income, workouts, journalDays = "journal_days", tasksDone = "tasks_done", xp, unsupported
}

public struct CoachAnswer: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var captureId: UUID
    public var question: String
    public var metric: CoachMetric
    public var startDate: LocalDate
    public var endDate: LocalDate
    public var value: Double?
    public var currency: String?
    public var explanation: String
}
