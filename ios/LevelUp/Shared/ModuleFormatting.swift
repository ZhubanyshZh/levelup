import Foundation
import LevelUpKit
import SwiftUI

// MARK: - Деньги

enum Money {
    /// «3 500 ₸», «12,50 $».
    static func text(_ amount: Double, currency: String) -> String {
        amount.formatted(.currency(code: currency).precision(.fractionLength(amount.rounded() == amount ? 0 : 2)))
    }

    /// Компактно для виджетов и графиков: «12,3 тыс. ₸».
    static func short(_ amount: Double, currency: String) -> String {
        if abs(amount) < 10_000 { return text(amount, currency: currency) }
        let number = amount.formatted(.number.notation(.compactName).precision(.significantDigits(3)))
        let symbol = Locale.current.currencySymbol(for: currency)
        return "\(number) \(symbol)"
    }
}

extension Locale {
    func currencySymbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = self
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }
}

extension MoneyCategory {
    var title: LocalizedStringKey {
        switch self {
        case .groceries: "Продукты"
        case .cafe: "Кафе и доставка"
        case .transport: "Транспорт"
        case .home: "Дом"
        case .bills: "Связь и счета"
        case .health: "Здоровье"
        case .clothes: "Одежда"
        case .fun: "Развлечения"
        case .education: "Обучение"
        case .sport: "Спорт"
        case .gifts: "Подарки"
        case .travel: "Путешествия"
        case .pets: "Питомцы"
        case .other: "Другое"
        case .salary: "Зарплата"
        case .freelance: "Подработка"
        case .gift: "Подарок"
        case .refund: "Возврат"
        case .otherIncome: "Другой доход"
        }
    }

    var symbol: String {
        switch self {
        case .groceries: "cart"
        case .cafe: "cup.and.saucer"
        case .transport: "car"
        case .home: "house"
        case .bills: "doc.text"
        case .health: "cross.case"
        case .clothes: "tshirt"
        case .fun: "gamecontroller"
        case .education: "graduationcap"
        case .sport: "dumbbell"
        case .gifts, .gift: "gift"
        case .travel: "airplane"
        case .pets: "pawprint"
        case .other, .otherIncome: "ellipsis.circle"
        case .salary: "banknote"
        case .freelance: "briefcase"
        case .refund: "arrow.uturn.backward.circle"
        }
    }

    var color: Color {
        switch self {
        case .groceries: .green
        case .cafe: .orange
        case .transport: .blue
        case .home: .brown
        case .bills: .indigo
        case .health: .red
        case .clothes: .pink
        case .fun: .purple
        case .education: .teal
        case .sport: .mint
        case .gifts, .gift: .yellow
        case .travel: .cyan
        case .pets: .orange
        case .other, .otherIncome: .gray
        case .salary, .freelance, .refund: .green
        }
    }
}

/// Название категории по ключу с сервера (неизвестный ключ — как «Другое»).
struct CategoryLabel: View {
    let key: String

    var body: some View {
        let category = MoneyCategory(rawValue: key) ?? .other
        Label {
            Text(category.title)
        } icon: {
            Image(systemName: category.symbol)
                .foregroundStyle(category.color)
        }
    }
}

// MARK: - Тренировки

enum WorkoutFormat {
    /// «80 кг × 5», «12 повт.», «2:00», «5 км».
    static func set(_ set: SetInput) -> String {
        var parts: [String] = []
        if let weight = set.weightKg {
            let kg = weight.formatted(.number.precision(.fractionLength(0...1)))
            parts.append(set.reps.map { String(localized: "\(kg) кг × \($0)") } ?? String(localized: "\(kg) кг"))
        } else if let reps = set.reps {
            parts.append(String(localized: "\(reps) повт."))
        }
        if let seconds = set.durationSec {
            parts.append(duration(seconds))
        }
        if let meters = set.distanceM {
            parts.append(distance(meters))
        }
        return parts.joined(separator: " · ")
    }

    static func set(_ set: WorkoutSet) -> String {
        Self.set(SetInput(exercise: set.exercise, weightKg: set.weightKg, reps: set.reps, durationSec: set.durationSec, distanceM: set.distanceM))
    }

    static func duration(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    static func distance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

// MARK: - Прокачка

extension Quest {
    /// «Закрой 10 задач», «Пиши дневник 4 дня» — текст задания.
    var title: String {
        switch questKind {
        case .tasks: String(localized: "Выполни задач: \(target)")
        case .journal: String(localized: "Дневник: \(target) дн.")
        case .workouts: String(localized: "Тренировок: \(target)")
        case .goalSteps: String(localized: "Шагов к целям: \(target)")
        case .comeback: String(localized: "Вернись: сделай что-нибудь сегодня")
        case nil: kind
        }
    }

    var symbol: String {
        switch questKind {
        case .tasks: "checkmark.circle"
        case .journal: "book"
        case .workouts: "figure.strengthtraining.traditional"
        case .goalSteps: "flag"
        case .comeback: "arrow.uturn.left.circle"
        case nil: "star"
        }
    }
}

/// Каталог достижений: название, условие, значок. Коды — как на сервере.
enum AchievementCatalog {
    static func title(_ code: String) -> String {
        switch code {
        case "first_task": String(localized: "Первый шаг")
        case "tasks_50": String(localized: "Деятель")
        case "tasks_200": String(localized: "Машина дел")
        case "journal_7": String(localized: "Неделя дневника")
        case "journal_30": String(localized: "Летописец")
        case "first_workout": String(localized: "Первая тренировка")
        case "workouts_10": String(localized: "В ритме")
        case "workouts_50": String(localized: "Железный")
        case "first_pr": String(localized: "Личный рекорд")
        case "budget_month": String(localized: "Месяц без перерасхода")
        case "goal_done": String(localized: "Цель достигнута")
        case "quests_10": String(localized: "Искатель приключений")
        case "streak_7": String(localized: "Неделя подряд")
        case "streak_30": String(localized: "Месяц подряд")
        case "level_5": String(localized: "Уровень 5")
        case "level_10": String(localized: "Уровень 10")
        case "level_20": String(localized: "Уровень 20")
        default: code
        }
    }

    static func detail(_ code: String) -> String {
        switch code {
        case "first_task": String(localized: "Выполни первую задачу")
        case "tasks_50": String(localized: "Выполни 50 задач")
        case "tasks_200": String(localized: "Выполни 200 задач")
        case "journal_7": String(localized: "7 дней дневника подряд")
        case "journal_30": String(localized: "30 дней дневника подряд")
        case "first_workout": String(localized: "Запиши первую тренировку")
        case "workouts_10": String(localized: "10 тренировок")
        case "workouts_50": String(localized: "50 тренировок")
        case "first_pr": String(localized: "Побей свой рекорд в упражнении")
        case "budget_month": String(localized: "4 недели подряд в рамках бюджета")
        case "goal_done": String(localized: "Достигни цели")
        case "quests_10": String(localized: "Выполни 10 квестов")
        case "streak_7": String(localized: "7 дней подряд с опытом")
        case "streak_30": String(localized: "30 дней подряд с опытом")
        case "level_5": String(localized: "Дойди до 5 уровня")
        case "level_10": String(localized: "Дойди до 10 уровня")
        case "level_20": String(localized: "Дойди до 20 уровня")
        default: ""
        }
    }

    static func symbol(_ code: String) -> String {
        switch code {
        case "first_task", "tasks_50", "tasks_200": "checkmark.seal.fill"
        case "journal_7", "journal_30": "book.closed.fill"
        case "first_workout", "workouts_10", "workouts_50": "figure.strengthtraining.traditional"
        case "first_pr": "trophy.fill"
        case "budget_month": "banknote.fill"
        case "goal_done": "flag.checkered"
        case "quests_10": "map.fill"
        case "streak_7", "streak_30": "flame.fill"
        default: "star.fill"
        }
    }
}

/// Ключи стандартных сфер. Названия и значки сфер приходят с сервера (их можно менять).
enum SphereKey {
    static let all = ["body", "mind", "finance", "discipline", "balance"]
}
