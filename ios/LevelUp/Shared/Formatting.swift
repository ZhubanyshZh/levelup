import Foundation
import LevelUpKit
import SwiftUI

enum DueFormat {
    /// «Сегодня, 14:00», «Завтра», «12 окт.», «Пт, 16 окт., 13:00».
    static func label(date: LocalDate?, time: String?) -> String? {
        guard let date else { return time }
        let today = LocalDate.today()
        let day: String
        switch date {
        case today: day = String(localized: "Сегодня")
        case today.adding(days: 1): day = String(localized: "Завтра")
        case today.adding(days: -1): day = String(localized: "Вчера")
        default:
            let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
            let withWeekday = date < today.adding(days: 7) && date > today ? style.weekday(.abbreviated) : style
            day = date.date().formatted(withWeekday)
        }
        return time.map { "\(day), \($0)" } ?? day
    }

    static func isOverdue(_ task: TaskItem) -> Bool {
        guard !task.isDone, let due = task.dueDate else { return false }
        return due < LocalDate.today()
    }
}

enum TimeText {
    /// «HH:MM» ↔ Date (сегодняшний день) — для DatePicker.
    static func date(from hhmm: String?) -> Date? {
        guard let hhmm else { return nil }
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: .now)
    }

    static func string(from date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

extension TaskStatus {
    var title: LocalizedStringKey {
        switch self {
        case .todo: "Сделать"
        case .doing: "В работе"
        case .done: "Готово"
        }
    }

    var symbol: String {
        switch self {
        case .todo: "circle"
        case .doing: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
        }
    }
}

extension TaskPriority {
    var title: LocalizedStringKey {
        switch self {
        case .low: "Низкий"
        case .normal: "Обычный"
        case .high: "Высокий"
        }
    }
}

extension Weekday {
    var title: String {
        let monday = LocalDate(year: 2026, month: 10, day: 5)
        let index = Weekday.allCases.firstIndex(of: self) ?? 0
        return monday.adding(days: index).date().formatted(.dateTime.weekday(.wide))
    }

    var shortTitle: String {
        // 2026-10-05 — понедельник; от него отсчитываем дни недели в языке устройства.
        let monday = LocalDate(year: 2026, month: 10, day: 5)
        let index = Weekday.allCases.firstIndex(of: self) ?? 0
        return monday.adding(days: index).date().formatted(.dateTime.weekday(.abbreviated))
    }
}

extension Schedule {
    var summary: String {
        let intervals = weekdays.sorted().map { interval(on: $0) }
        let busyText = busy ? " · " + String(localized: "занят") : ""
        if let first = intervals.first, intervals.contains(where: { $0.start != first.start || $0.end != first.end }) {
            return intervals.map { "\($0.weekday.shortTitle) \($0.start)–\($0.end)" }.joined(separator: " · ") + busyText
        }
        let days = weekdays.count == 7
            ? String(localized: "Каждый день")
            : weekdays.sorted().map(\.shortTitle).joined(separator: ", ")
        return "\(days) \(intervals.first?.start ?? start)–\(intervals.first?.end ?? end)\(busyText)"
    }
}

extension FactCategory {
    var title: LocalizedStringKey {
        switch self {
        case .schedule: "Распорядок"
        case .preference: "Предпочтения"
        case .health: "Здоровье и питание"
        case .finance: "Финансы"
        case .focus: "Фокус и ценности"
        case .personal: "Личное"
        }
    }

    var symbol: String {
        switch self {
        case .schedule: "calendar.badge.clock"
        case .preference: "heart"
        case .health: "cross.case"
        case .finance: "banknote"
        case .focus: "scope"
        case .personal: "person"
        }
    }
}

extension CaptureItemKind {
    var title: LocalizedStringKey {
        switch self {
        case .task: "Задача"
        case .profileFact: "Факт о тебе"
        case .journal: "Дневник"
        case .shopping: "Покупки"
        case .expense: "Трата"
        case .income: "Доход"
        case .workout: "Тренировка"
        case .goal: "Цель"
        case .question: "Вопрос"
        case .note: "Заметка"
        }
    }

    var symbol: String {
        switch self {
        case .task: "checkmark.circle"
        case .profileFact: "person.text.rectangle"
        case .journal: "book"
        case .shopping: "cart"
        case .expense: "creditcard"
        case .income: "banknote"
        case .workout: "figure.strengthtraining.traditional"
        case .goal: "flag"
        case .question: "questionmark.bubble"
        case .note: "note.text"
        }
    }
}

extension AIProviderKind {
    var title: String {
        switch self {
        case .gemini: "Google Gemini"
        case .openai: "OpenAI"
        }
    }

    var keysURL: URL {
        switch self {
        case .gemini: URL(string: "https://aistudio.google.com/apikey")!
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        }
    }
}

enum Mood {
    static func emoji(_ value: Int) -> String {
        ["😞", "🙁", "😐", "🙂", "😄"][min(max(value, 1), 5) - 1]
    }

    static func color(_ value: Int) -> Color {
        [Color.red, .orange, .yellow, .mint, .green][min(max(value, 1), 5) - 1]
    }

    static func batterySymbol(_ value: Int) -> String {
        ["battery.0percent", "battery.25percent", "battery.50percent", "battery.75percent", "battery.100percent"][min(max(value, 1), 5) - 1]
    }

    static func title(_ value: Int) -> LocalizedStringKey {
        switch value {
        case 1: "Очень плохо"
        case 2: "Плохо"
        case 3: "Нормально"
        case 4: "Хорошо"
        default: "Отлично"
        }
    }
}

extension Recurrence {
    var summary: String {
        switch freq {
        case .daily:
            return String(localized: "Каждый день")
        case .weekly:
            if weekdays.count == 7 { return String(localized: "Каждый день") }
            if weekdays.isEmpty { return String(localized: "Каждую неделю") }
            let days = weekdays.sorted().map(\.shortTitle).joined(separator: ", ")
            return String(localized: "Каждую неделю: \(days)")
        case .monthly:
            if let monthday {
                return String(localized: "Каждый месяц, \(monthday)-го")
            }
            return String(localized: "Каждый месяц")
        }
    }
}

extension Recurrence.Frequency {
    var title: LocalizedStringKey {
        switch self {
        case .daily: "Каждый день"
        case .weekly: "Каждую неделю"
        case .monthly: "Каждый месяц"
        }
    }
}
