import Foundation
import LevelUpKit
import Observation

/// Финансы выбранного месяца: операции и сводка (траты по дням и категориям, бюджеты).
@MainActor
@Observable
final class FinanceStore {
    /// Первый день показываемого месяца.
    private(set) var month: LocalDate
    private(set) var transactions: [MoneyTransaction]
    private(set) var summary: FinanceSummary?
    var errorMessage: String?

    private let api: APIClient
    private let cache = LocalCache<[MoneyTransaction]>(name: "transactions")
    private let summaryCache = LocalCache<FinanceSummary>(name: "finance-summary")
    var onUnauthorized: () -> Void = {}
    var onChange: () -> Void = {}

    init(api: APIClient) {
        self.api = api
        let today = LocalDate.today()
        month = LocalDate(year: today.year, month: today.month, day: 1)
        transactions = cache.load() ?? []
        summary = summaryCache.load()
    }

    var isCurrentMonth: Bool {
        let today = LocalDate.today()
        return month.year == today.year && month.month == today.month
    }

    /// Операции по дням, свежие сверху.
    var byDay: [(day: LocalDate, items: [MoneyTransaction])] {
        Dictionary(grouping: transactions, by: \.occurredOn)
            .map { ($0.key, $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.0 > $1.0 }
    }

    func load() async {
        do {
            async let rows = api.transactions(month: month)
            async let totals = api.financeSummary(month: month)
            let (loadedRows, loadedSummary) = try await (rows, totals)
            apply(rows: loadedRows, summary: loadedSummary)
        } catch {
            report(error)
        }
    }

    func show(monthOffset: Int) async {
        let shifted = Calendar.current.date(byAdding: .month, value: monthOffset, to: month.date()) ?? .now
        month = LocalDate(shifted)
        transactions = []
        summary = nil
        await load()
    }

    func save(_ input: TransactionInput, editing: MoneyTransaction?) async -> Bool {
        do {
            if let editing {
                _ = try await api.updateTransaction(id: editing.id, input)
            } else {
                _ = try await api.createTransaction(input)
            }
            await load()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func delete(_ row: MoneyTransaction) async {
        transactions.removeAll { $0.id == row.id }
        do {
            try await api.deleteTransaction(id: row.id)
        } catch {
            report(error)
        }
        await load()
    }

    func setBudget(_ category: MoneyCategory?, limit: Double?) async {
        do {
            let updated = if let limit, limit > 0 {
                try await api.setBudget(BudgetInput(category: category, monthlyLimit: limit))
            } else {
                try await api.deleteBudget(category: category)
            }
            if isCurrentMonth {
                summary = updated
                summaryCache.save(updated)
                onChange()
            }
        } catch {
            report(error)
        }
    }

    /// Операции из записи голосом — сразу в список, сводка догонит.
    func insert(_ created: [MoneyTransaction]) {
        guard !created.isEmpty else { return }
        Task { await load() }
    }

    func reset() {
        transactions = []
        summary = nil
    }

    private func apply(rows: [MoneyTransaction], summary: FinanceSummary) {
        transactions = rows
        self.summary = summary
        if isCurrentMonth {
            cache.save(rows)
            summaryCache.save(summary)
            onChange()
        }
    }

    private func report(_ error: Error) {
        if (error as? APIError)?.isUnauthorized == true {
            onUnauthorized()
        } else {
            errorMessage = ErrorText.message(for: error)
        }
    }
}
