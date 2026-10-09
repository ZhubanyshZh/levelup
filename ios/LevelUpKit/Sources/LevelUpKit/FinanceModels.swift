import Foundation

public enum TransactionKind: String, Codable, Sendable, CaseIterable {
    case expense, income
}

/// Ключи категорий совпадают с сервером. Названия и значки — в приложении.
public enum MoneyCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case groceries, cafe, transport, home, bills, health, clothes, fun, education, sport, gifts, travel, pets, other
    case salary, freelance, gift, refund
    case otherIncome = "other_income"

    public var id: String { rawValue }

    public static let expenses: [MoneyCategory] = [
        .groceries, .cafe, .transport, .home, .bills, .health, .clothes, .fun, .education, .sport, .gifts, .travel, .pets, .other,
    ]
    public static let incomes: [MoneyCategory] = [.salary, .freelance, .gift, .refund, .otherIncome]

    public var kind: TransactionKind { Self.incomes.contains(self) ? .income : .expense }
}

public struct MoneyTransaction: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var kind: TransactionKind
    public var amount: Double
    public var currency: String
    /// Строкой: новая категория на сервере не должна ломать старое приложение.
    public var category: String
    public var note: String?
    public var occurredOn: LocalDate
    public var captureId: UUID?
    public let createdAt: Date
    public var updatedAt: Date

    public var moneyCategory: MoneyCategory? { MoneyCategory(rawValue: category) }
}

public struct TransactionInput: Encodable, Sendable {
    public var kind: TransactionKind
    public var amount: Double
    public var currency: String?
    public var category: MoneyCategory
    public var note: String?
    public var occurredOn: LocalDate

    public init(kind: TransactionKind, amount: Double, currency: String? = nil, category: MoneyCategory, note: String? = nil, occurredOn: LocalDate) {
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.category = category
        self.note = note
        self.occurredOn = occurredOn
    }

    private enum CodingKeys: String, CodingKey {
        case kind, amount, currency, category, note, occurredOn
    }

    // Пустая заметка уходит как null — так её можно очистить.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(amount, forKey: .amount)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encode(category, forKey: .category)
        try container.encode(note, forKey: .note)
        try container.encode(occurredOn, forKey: .occurredOn)
    }
}

public struct BudgetInput: Encodable, Sendable {
    public var category: MoneyCategory?
    public var monthlyLimit: Double

    public init(category: MoneyCategory?, monthlyLimit: Double) {
        self.category = category
        self.monthlyLimit = monthlyLimit
    }

    private enum CodingKeys: String, CodingKey {
        case category, monthlyLimit
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(category, forKey: .category)
        try container.encode(monthlyLimit, forKey: .monthlyLimit)
    }
}

public struct BudgetStatus: Codable, Sendable, Hashable {
    public var category: String?
    public var monthlyLimit: Double
    public var currency: String
    public var spent: Double
    public var remaining: Double
}

public struct CategoryTotal: Codable, Sendable, Hashable {
    public var category: String
    public var amount: Double
}

public struct DayTotal: Codable, Sendable, Hashable {
    public var date: LocalDate
    public var spent: Double
    public var income: Double
}

public struct CurrencyTotal: Codable, Sendable, Hashable {
    public var currency: String
    public var spent: Double
    public var income: Double
}

public struct FinanceSummary: Codable, Sendable, Hashable {
    public var month: String
    public var currency: String
    public var spent: Double
    public var income: Double
    public var spentToday: Double
    public var spentWeek: Double
    /// Сколько можно тратить в неделю, чтобы уложиться в общий бюджет.
    public var weekAllowance: Double?
    public var expensesByCategory: [CategoryTotal]
    public var incomeByCategory: [CategoryTotal]
    public var byDay: [DayTotal]
    public var budgets: [BudgetStatus]
    public var otherCurrencies: [CurrencyTotal]

    public var totalBudget: BudgetStatus? { budgets.first { $0.category == nil } }

    public static func empty(currency: String, month: LocalDate = .today()) -> FinanceSummary {
        FinanceSummary(
            month: String(format: "%04d-%02d", month.year, month.month),
            currency: currency, spent: 0, income: 0, spentToday: 0, spentWeek: 0, weekAllowance: nil,
            expensesByCategory: [], incomeByCategory: [], byDay: [], budgets: [], otherCurrencies: []
        )
    }
}
