import LevelUpKit
import SwiftUI
import WidgetKit

/// Заголовок виджета: значок и название цветом приложения, справа — дополнительная строка.
struct WidgetHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .foregroundStyle(Brand.accent)
                .widgetAccentable()
            Spacer(minLength: 4)
            trailing
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

extension WidgetHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey, systemImage: String) {
        self.init(title: title, systemImage: systemImage) { EmptyView() }
    }
}

/// Вместо данных, если вход не выполнен или App Group недоступна.
struct WidgetUnavailableView: View {
    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(verbatim: "Level Up")
            } icon: {
                Image(systemName: "chevron.up.2")
            }
            .font(.caption.bold())
            .foregroundStyle(Brand.accent)
            Spacer(minLength: 0)
            if entry.isAppGroupAvailable {
                Text("Войди в приложение")
            } else {
                Text("Нет доступа к данным приложения")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Строка задачи с кнопкой ✓: отметка уходит на сервер и приносит опыт.
struct WidgetTaskRow: View {
    let task: WidgetSnapshot.TaskEntry
    let day: LocalDate

    private var isDone: Bool { task.doneOn != nil }

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleTaskIntent(taskID: task.id)) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(isDone ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(.secondary))
                    .widgetAccentable()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? Text("Вернуть в работу") : Text("Отметить выполненной"))

            Text(task.title)
                .font(.subheadline)
                .lineLimit(1)
                .strikethrough(isDone)
                .foregroundStyle(isDone ? .secondary : .primary)
            if task.isImportant && !isDone {
                Image(systemName: "exclamationmark")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 4)
            if let label = dueLabel {
                Text(label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isOverdue ? .red : .secondary)
            }
        }
    }

    private var isOverdue: Bool {
        guard !isDone, let due = task.dueDate else { return false }
        return due < day
    }

    private var dueLabel: String? {
        guard let due = task.dueDate else { return nil }
        if due < day {
            return due.date().formatted(.dateTime.day().month(.abbreviated))
        }
        return task.dueTime
    }
}

/// Строка покупки с кнопкой ✓.
struct WidgetShoppingRow: View {
    let item: WidgetSnapshot.ShoppingEntry
    var showsQuantity = false

    var body: some View {
        Button(intent: ToggleShoppingIntent(itemID: item.id)) {
            HStack(spacing: 6) {
                Image(systemName: item.isBought ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isBought ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(.secondary))
                    .widgetAccentable()
                Text(item.name)
                    .lineLimit(1)
                    .strikethrough(item.isBought)
                    .foregroundStyle(item.isBought ? .secondary : .primary)
                if showsQuantity, let quantity = item.quantity {
                    Text(quantity)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Фон виджетов: системный, светлый или тёмный — как у виджетов Apple.
    func levelUpWidgetBackground() -> some View {
        containerBackground(.background, for: .widget)
    }
}

// MARK: - Данные для галереи виджетов

extension WidgetSnapshot {
    static let preview: WidgetSnapshot = {
        let today = LocalDate.today()
        var snapshot = WidgetSnapshot(
            isSignedIn: true,
            displayName: nil,
            level: 7,
            xp: 640,
            xpForNextLevel: 1852,
            todayXp: 35,
            todayXpDate: today,
            tasks: [
                TaskEntry(id: UUID(), title: String(localized: "Позвонить в банк"), dueDate: today, dueTime: "09:30", isImportant: true),
                TaskEntry(id: UUID(), title: String(localized: "Отправить отчёт"), dueDate: today, dueTime: "15:00"),
                TaskEntry(id: UUID(), title: String(localized: "Тренировка"), dueDate: today, dueTime: "19:00", isRepeating: true),
                TaskEntry(id: UUID(), title: String(localized: "Прочитать главу книги"), dueDate: today),
            ],
            shopping: [
                ShoppingEntry(id: UUID(), name: String(localized: "Молоко")),
                ShoppingEntry(id: UUID(), name: String(localized: "Хлеб"), quantity: "2"),
                ShoppingEntry(id: UUID(), name: String(localized: "Яблоки"), quantity: String(localized: "1 кг")),
                ShoppingEntry(id: UUID(), name: String(localized: "Корм коту")),
            ],
            journalDays: (1...4).map { today.adding(days: -$0) },
            busy: [
                BusySlot(title: String(localized: "Обед"), weekdays: Weekday.allCases, start: "13:00", end: "14:00"),
            ]
        )
        snapshot.tasks[0].doneOn = today
        snapshot.finance = FinanceEntry(
            currency: "KZT", month: LocalDate(year: today.year, month: today.month, day: 1), day: today,
            spentMonth: 184_500, spentToday: 4_700, monthlyBudget: 300_000
        )
        snapshot.workouts = WorkoutEntry(
            days: [today.adding(days: -2), today], lastTitle: String(localized: "Силовая"), lastDate: today,
            lastRecord: String(localized: "Жим лёжа"), activeSince: nil
        )
        snapshot.goals = [GoalEntry(id: UUID(), title: String(localized: "Пробежать 10 км"), progress: 0.6, deadline: today.adding(days: 45), icon: "💪")]
        snapshot.quests = [
            QuestEntry(id: UUID(), title: String(localized: "Выполни задач: 3"), isDaily: true, periodEnd: today, progress: 2, target: 3, reward: 50, isDone: false),
            QuestEntry(id: UUID(), title: String(localized: "Тренировок: 3"), isDaily: false, periodEnd: today.adding(days: 3), progress: 3, target: 3, reward: 150, isDone: true),
            QuestEntry(id: UUID(), title: String(localized: "Дневник: 5 дн."), isDaily: false, periodEnd: today.adding(days: 3), progress: 2, target: 5, reward: 100, isDone: false),
        ]
        snapshot.streakDays = 6
        return snapshot
    }()
}
