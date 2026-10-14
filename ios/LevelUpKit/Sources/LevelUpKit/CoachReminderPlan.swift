import Foundation

/// Ближайшие семь дней. Если весь утренний/вечерний интервал занят, пропускаем напоминание.
public enum CoachReminderPlan {
    public struct Event: Sendable, Equatable {
        public let kind: CoachKind
        public let date: Date
    }

    public static func events(now: Date = .now, schedules: [Schedule], calendar: Calendar = .current) -> [Event] {
        let horizon = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        let today = calendar.startOfDay(for: now)
        var result: [Event] = []
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            var windows: [(CoachKind, Int, Int)] = [(.morning, 9, 12), (.evening, 21, 23)]
            if calendar.component(.weekday, from: day) == 2 { windows.append((.weekly, 10, 13)) }
            for (kind, start, end) in windows {
                guard var candidate = calendar.date(bySettingHour: start, minute: 0, second: 0, of: day) else { continue }
                while calendar.component(.hour, from: candidate) < end {
                    if candidate > now && candidate < horizon && !isBusy(candidate, schedules: schedules, calendar: calendar) {
                        result.append(Event(kind: kind, date: candidate))
                        break
                    }
                    guard let later = calendar.date(byAdding: .minute, value: 15, to: candidate) else { break }
                    candidate = later
                }
            }
        }
        return Array(result.sorted { $0.date < $1.date }.prefix(15))
    }

    private static func isBusy(_ date: Date, schedules: [Schedule], calendar: Calendar) -> Bool {
        let day = LocalDate(date, calendar: calendar)
        let previous = day.adding(days: -1, calendar: calendar)
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return schedules.contains { schedule in
            guard schedule.busy else { return false }
            return schedule.weekdays.contains { weekday in
                let interval = schedule.interval(on: weekday)
                guard let start = minutes(interval.start), let end = minutes(interval.end) else { return false }
                if start < end { return weekday == day.weekday && minute >= start && minute < end }
                return (weekday == day.weekday && minute >= start) || (weekday == previous.weekday && minute < end)
            }
        }
    }

    private static func minutes(_ string: String) -> Int? {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }
}
