import Charts
import LevelUpKit
import SwiftUI

struct FinanceView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: MoneyTransaction?
    @State private var isAdding = false
    @State private var isEditingBudgets = false

    var body: some View {
        @Bindable var finance = store.finance
        List {
            Section {
                MonthSwitcher(month: finance.month, canGoForward: !finance.isCurrentMonth) { offset in
                    Task { await finance.show(monthOffset: offset) }
                }
                .listRowSeparator(.hidden)
                if let summary = finance.summary {
                    SummaryCard(summary: summary, isCurrentMonth: finance.isCurrentMonth)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }

            if let summary = finance.summary, !summary.byDay.isEmpty {
                Section("По дням") {
                    DailyChart(summary: summary, month: finance.month)
                        .frame(height: 160)
                        .padding(.vertical, 4)
                }
            }

            if let summary = finance.summary, !summary.expensesByCategory.isEmpty {
                Section("Траты по категориям") {
                    ForEach(summary.expensesByCategory, id: \.category) { total in
                        CategoryRow(total: total, currency: summary.currency, of: summary.spent, budget: summary.budgets.first { $0.category == total.category })
                    }
                }
            }

            ForEach(finance.byDay, id: \.day) { group in
                Section {
                    ForEach(group.items) { row in
                        TransactionRow(row: row)
                            .contentShape(.rect)
                            .onTapGesture { editing = row }
                            .swipeActions {
                                Button("Удалить", systemImage: "trash", role: .destructive) {
                                    Task { await finance.delete(row) }
                                }
                            }
                    }
                } header: {
                    Text(DueFormat.label(date: group.day, time: nil) ?? "")
                }
            }
        }
        .overlay {
            if finance.transactions.isEmpty, finance.summary != nil {
                ContentUnavailableView(
                    "Пока пусто",
                    systemImage: "creditcard",
                    description: Text("Скажи «потратил 3500 на такси» в «Записать» или нажми «+».")
                )
                .allowsHitTesting(false)
            }
        }
        .navigationTitle("Финансы")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isEditingBudgets = true
                } label: {
                    Label("Бюджет", systemImage: "chart.pie")
                }
                Button {
                    isAdding = true
                } label: {
                    Label("Новая операция", systemImage: "plus")
                }
            }
        }
        .refreshable { await finance.load() }
        .task { await finance.load() }
        .sheet(item: $editing) { TransactionEditorView(row: $0) }
        .sheet(isPresented: $isAdding) { TransactionEditorView(row: nil) }
        .sheet(isPresented: $isEditingBudgets) { BudgetView() }
        .overlay(alignment: .bottom) { ErrorBanner(message: $finance.errorMessage) }
    }
}

private struct MonthSwitcher: View {
    let month: LocalDate
    let canGoForward: Bool
    let onShift: (Int) -> Void

    var body: some View {
        HStack {
            Button { onShift(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel(Text("Предыдущий месяц"))
            Spacer()
            Text(month.date().formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button { onShift(1) } label: { Image(systemName: "chevron.right") }
                .disabled(!canGoForward)
                .accessibilityLabel(Text("Следующий месяц"))
        }
        .buttonStyle(.borderless)
    }
}

private struct SummaryCard: View {
    let summary: FinanceSummary
    let isCurrentMonth: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Потрачено")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Money.text(summary.spent, currency: summary.currency))
                        .font(.title2.bold())
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Доход")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Money.text(summary.income, currency: summary.currency))
                        .font(.headline)
                        .foregroundStyle(.green)
                }
            }

            if let budget = summary.totalBudget {
                ProgressView(value: min(budget.spent / max(budget.monthlyLimit, 1), 1))
                    .tint(budget.remaining < 0 ? .red : .accentColor)
                Text(budget.remaining >= 0
                     ? String(localized: "Осталось \(Money.text(budget.remaining, currency: summary.currency)) из \(Money.text(budget.monthlyLimit, currency: summary.currency))")
                     : String(localized: "Перерасход \(Money.text(-budget.remaining, currency: summary.currency))"))
                    .font(.caption)
                    .foregroundStyle(budget.remaining < 0 ? .red : .secondary)
            }

            if isCurrentMonth {
                HStack {
                    Label(Money.text(summary.spentToday, currency: summary.currency), systemImage: "sun.max")
                    Spacer()
                    if let allowance = summary.weekAllowance {
                        Label {
                            Text("Неделя: \(Money.short(summary.spentWeek, currency: summary.currency)) из \(Money.short(allowance, currency: summary.currency))")
                        } icon: {
                            Image(systemName: summary.spentWeek <= allowance ? "checkmark.seal" : "exclamationmark.triangle")
                        }
                        .foregroundStyle(summary.spentWeek <= allowance ? Color.secondary : .orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if summary.weekAllowance != nil {
                    Text("Неделя в рамках бюджета — +50 XP.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            ForEach(summary.otherCurrencies, id: \.currency) { other in
                Text("Ещё в \(other.currency): −\(Money.text(other.spent, currency: other.currency)), +\(Money.text(other.income, currency: other.currency))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DailyChart: View {
    let summary: FinanceSummary
    let month: LocalDate

    var body: some View {
        Chart(summary.byDay, id: \.date) { day in
            BarMark(
                x: .value("День", day.date.date(), unit: .day),
                y: .value("Потрачено", day.spent)
            )
            .foregroundStyle(Color.accentColor.gradient)
            .cornerRadius(3)
        }
        .chartXScale(domain: monthDomain)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(Money.short(amount, currency: summary.currency))
                    }
                }
            }
        }
    }

    private var monthDomain: ClosedRange<Date> {
        let start = month.date()
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
        return start...end
    }
}

private struct CategoryRow: View {
    let total: CategoryTotal
    let currency: String
    let of: Double
    let budget: BudgetStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CategoryLabel(key: total.category)
                Spacer()
                Text(Money.text(total.amount, currency: currency))
                    .monospacedDigit()
            }
            if let budget {
                ProgressView(value: min(total.amount / max(budget.monthlyLimit, 1), 1))
                    .tint(budget.remaining < 0 ? .red : (MoneyCategory(rawValue: total.category) ?? .other).color)
                Text(budget.remaining >= 0
                     ? String(localized: "Лимит \(Money.text(budget.monthlyLimit, currency: currency)), осталось \(Money.text(budget.remaining, currency: currency))")
                     : String(localized: "Лимит превышен на \(Money.text(-budget.remaining, currency: currency))"))
                    .font(.caption2)
                    .foregroundStyle(budget.remaining < 0 ? .red : .secondary)
            } else {
                ProgressView(value: of > 0 ? total.amount / of : 0)
                    .tint((MoneyCategory(rawValue: total.category) ?? .other).color)
            }
        }
    }
}

struct TransactionRow: View {
    let row: MoneyTransaction

    var body: some View {
        let category = row.moneyCategory ?? .other
        HStack(spacing: 12) {
            Image(systemName: category.symbol)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(category.color.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.note ?? "")
                    .lineLimit(1)
                Text(category.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text((row.kind == .income ? "+" : "−") + Money.text(row.amount, currency: row.currency))
                .monospacedDigit()
                .foregroundStyle(row.kind == .income ? .green : .primary)
        }
    }
}

// MARK: - Редактор операции

struct TransactionEditorView: View {
    let row: MoneyTransaction?

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: TransactionKind = .expense
    @State private var amount: Double?
    @State private var category: MoneyCategory = .groceries
    @State private var note = ""
    @State private var date = Date.now
    @State private var isSaving = false
    private enum Field: Hashable { case amount, note }
    @FocusState private var focusedField: Field?

    private var currency: String {
        row?.currency ?? store.finance.summary?.currency ?? "KZT"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Тип", selection: $kind) {
                        Text("Расход").tag(TransactionKind.expense)
                        Text("Доход").tag(TransactionKind.income)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _, newKind in
                        if category.kind != newKind {
                            category = newKind == .expense ? .groceries : .salary
                        }
                    }
                    TextField("Сумма", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                        .font(.title.bold())
                        .focused($focusedField, equals: .amount)
                    TextField("На что", text: $note)
                        .focused($focusedField, equals: .note)
                        .submitLabel(.done)
                }

                Section("Категория") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(kind == .expense ? MoneyCategory.expenses : MoneyCategory.incomes) { item in
                            Button {
                                category = item
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: item.symbol)
                                        .font(.title3)
                                    Text(item.title)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .foregroundStyle(category == item ? .white : item.color)
                                .background(category == item ? AnyShapeStyle(item.color.gradient) : AnyShapeStyle(item.color.opacity(0.12)), in: .rect(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    DatePicker("Дата", selection: $date, in: ...Date.now, displayedComponents: .date)
                }

                if let row {
                    Section {
                        Button("Удалить операцию", role: .destructive) {
                            Task {
                                await store.finance.delete(row)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .keyboardDismissal(isFocused: focusedField != nil) { focusedField = nil }
            .navigationTitle(row != nil ? "Операция" : kind == .expense ? "Трата" : "Доход")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                        .disabled((amount ?? 0) <= 0 || isSaving)
                }
            }
            .onAppear(perform: fill)
        }
    }

    private func fill() {
        guard let row else {
            focusedField = .amount
            return
        }
        kind = row.kind
        amount = row.amount
        category = row.moneyCategory ?? (row.kind == .expense ? .other : .otherIncome)
        note = row.note ?? ""
        date = row.occurredOn.date()
    }

    private func save() async {
        guard let amount, amount > 0 else { return }
        focusedField = nil
        isSaving = true
        defer { isSaving = false }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = TransactionInput(
            kind: kind,
            amount: amount,
            currency: currency,
            category: category,
            note: trimmed.isEmpty ? nil : trimmed,
            occurredOn: LocalDate(date)
        )
        if await store.finance.save(input, editing: row) {
            dismiss()
        }
    }
}

// MARK: - Бюджеты

struct BudgetView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var total: Double?
    @State private var limits: [MoneyCategory: Double] = [:]
    private enum Field: Hashable { case total, category(MoneyCategory) }
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Без лимита", value: $total, format: .number)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .total)
                } header: {
                    Text("Всего в месяц")
                } footer: {
                    Text("Каждая неделя, когда траты уложились в бюджет, приносит +50 XP. Пустое поле — без лимита.")
                }

                Section("По категориям") {
                    ForEach(MoneyCategory.expenses) { category in
                        HStack {
                            CategoryLabel(key: category.rawValue)
                            Spacer()
                            TextField("—", value: Binding(get: { limits[category] }, set: { limits[category] = $0 }), format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 120)
                                .focused($focusedField, equals: .category(category))
                        }
                    }
                }
            }
            .keyboardDismissal(isFocused: focusedField != nil) { focusedField = nil }
            .navigationTitle("Бюджет")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                }
            }
            .onAppear(perform: fill)
        }
    }

    private var budgets: [BudgetStatus] { store.finance.summary?.budgets ?? [] }

    private func fill() {
        total = budgets.first { $0.category == nil }?.monthlyLimit
        for budget in budgets {
            if let key = budget.category, let category = MoneyCategory(rawValue: key) {
                limits[category] = budget.monthlyLimit
            }
        }
    }

    private func save() async {
        let finance = store.finance
        focusedField = nil
        if total != budgets.first(where: { $0.category == nil })?.monthlyLimit {
            await finance.setBudget(nil, limit: total)
        }
        for category in MoneyCategory.expenses {
            let old = budgets.first { $0.category == category.rawValue }?.monthlyLimit
            if limits[category] != old {
                await finance.setBudget(category, limit: limits[category])
            }
        }
        dismiss()
    }
}
