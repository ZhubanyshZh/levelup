import AppIntents
import LevelUpKit
import SwiftUI
import WidgetKit

// MARK: - Финансы

/// «Финансы»: потрачено сегодня и за месяц, остаток бюджета, кнопка «+ трата».
struct FinanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FinanceWidget", provider: SnapshotProvider()) { entry in
            FinanceWidgetView(entry: entry)
                .levelUpWidgetBackground()
        }
        .configurationDisplayName("Финансы")
        .description("Траты за день и месяц, остаток бюджета.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FinanceWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var currency: String { snapshot.finance?.currency ?? "KZT" }
    private var month: Double { snapshot.spentMonth(on: entry.day) }
    private var budget: Double? { snapshot.finance?.monthlyBudget }

    var body: some View {
        Group {
            if !snapshot.isSignedIn {
                WidgetUnavailableView(entry: entry)
            } else if family == .systemMedium {
                HStack(spacing: 16) {
                    numbers
                    Spacer(minLength: 0)
                    addButton
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    numbers
                    Spacer(minLength: 4)
                    addButton
                }
            }
        }
        .widgetURL(AppRoute.finance.url)
    }

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "Финансы", systemImage: "creditcard.fill")
            Text("Сегодня")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(WidgetMoney.text(snapshot.spentToday(on: entry.day), currency: currency))
                .font(.title3.bold().monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let budget {
                ProgressView(value: min(month / max(budget, 1), 1))
                    .tint(month > budget ? .red : Brand.accent)
                    .widgetAccentable()
                Text(month <= budget
                     ? String(localized: "Осталось \(WidgetMoney.short(budget - month, currency: currency))")
                     : String(localized: "Перерасход \(WidgetMoney.short(month - budget, currency: currency))"))
                    .font(.caption2)
                    .foregroundStyle(month > budget ? .red : .secondary)
            } else {
                Text("За месяц \(WidgetMoney.short(month, currency: currency))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var addButton: some View {
        Link(destination: AppRoute.capture(.expense).url) {
            Label("Трата", systemImage: "plus")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Brand.accent.gradient, in: .capsule)
                .widgetAccentable()
        }
    }
}

enum WidgetMoney {
    static func text(_ amount: Double, currency: String) -> String {
        amount.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }

    static func short(_ amount: Double, currency: String) -> String {
        if abs(amount) < 10_000 { return text(amount, currency: currency) }
        let number = amount.formatted(.number.notation(.compactName).precision(.significantDigits(3)))
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return "\(number) \(formatter.currencySymbol ?? currency)"
    }
}

// MARK: - Тренировки

/// «Тренировки»: сколько за неделю, последняя, свежий рекорд; кнопка «Начать».
struct WorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WorkoutWidget", provider: SnapshotProvider()) { entry in
            WorkoutWidgetView(entry: entry)
                .levelUpWidgetBackground()
        }
        .configurationDisplayName("Тренировки")
        .description("Тренировки за неделю, последняя и рекорд.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WorkoutWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var workouts: WidgetSnapshot.WorkoutEntry? { entry.snapshot.workouts }

    var body: some View {
        Group {
            if !entry.snapshot.isSignedIn {
                WidgetUnavailableView(entry: entry)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        WidgetHeader(title: "Тренировки", systemImage: "figure.strengthtraining.traditional")
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(entry.snapshot.workoutsThisWeek(on: entry.day), format: .number)
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                            Text("за неделю")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        startButton
                    }
                    if family == .systemMedium {
                        VStack(alignment: .leading, spacing: 6) {
                            if let title = workouts?.lastTitle, let date = workouts?.lastDate {
                                Text("Последняя")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(title)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                Text(date.date(), format: .dateTime.day().month())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let record = workouts?.lastRecord {
                                Label(record, systemImage: "trophy.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .widgetURL(AppRoute.workout.url)
    }

    private var startButton: some View {
        Link(destination: AppRoute.workout.url) {
            Label(workouts?.activeSince == nil ? "Начать" : "Идёт", systemImage: workouts?.activeSince == nil ? "play.fill" : "timer")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Brand.accent.gradient, in: .capsule)
                .widgetAccentable()
        }
    }
}

// MARK: - Квесты

struct QuestsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuestsWidget", provider: SnapshotProvider()) { entry in
            QuestsWidgetView(entry: entry)
                .levelUpWidgetBackground()
        }
        .configurationDisplayName("Квесты")
        .description("Задания на день и неделю и как они продвигаются.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuestsWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let quests = entry.snapshot.quests(on: entry.day)
        Group {
            if !entry.snapshot.isSignedIn {
                WidgetUnavailableView(entry: entry)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(title: "Квесты", systemImage: "map.fill") {
                        if entry.snapshot.streakDays > 0 {
                            Label("\(entry.snapshot.streakDays)", systemImage: "flame.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    if quests.isEmpty {
                        Spacer(minLength: 0)
                        Text("Открой приложение — квесты обновятся")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(quests.prefix(family == .systemMedium ? 4 : 2)) { quest in
                            QuestLine(quest: quest, compact: family == .systemSmall)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .widgetURL(AppRoute.progress.url)
    }
}

private struct QuestLine: View {
    let quest: WidgetSnapshot.QuestEntry
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if quest.isDone {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                Text(quest.title)
                    .lineLimit(1)
                    .strikethrough(quest.isDone)
                Spacer(minLength: 2)
                if !compact {
                    Text("\(quest.progress)/\(quest.target)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            ProgressView(value: Double(quest.progress) / Double(max(quest.target, 1)))
                .tint(quest.isDone ? .green : Brand.accent)
                .widgetAccentable()
        }
    }
}

// MARK: - Цель (с выбором цели)

struct GoalEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Цель"
    static let defaultQuery = GoalQuery()

    var id: UUID
    var title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct GoalQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [GoalEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [GoalEntity] {
        all()
    }

    private func all() -> [GoalEntity] {
        (SnapshotProvider.store.read()?.goals ?? []).map { GoalEntity(id: $0.id, title: $0.title) }
    }
}

struct SelectGoalIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Цель"
    static let description = IntentDescription("Какую цель показывать.")

    @Parameter(title: "Цель")
    var goal: GoalEntity?
}

struct GoalProvider: AppIntentTimelineProvider {
    private let base = SnapshotProvider()

    func placeholder(in context: Context) -> SnapshotEntry {
        base.placeholder(in: context)
    }

    func snapshot(for configuration: SelectGoalIntent, in context: Context) async -> SnapshotEntry {
        var entry = context.isPreview ? base.placeholder(in: context) : base.current()
        entry.selection = configuration.goal?.id.uuidString
        return entry
    }

    func timeline(for configuration: SelectGoalIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        let entries = base.entries().map { entry in
            var entry = entry
            entry.selection = configuration.goal?.id.uuidString
            return entry
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

/// «Цель»: прогресс выбранной цели и сколько дней осталось.
struct GoalWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "GoalWidget", intent: SelectGoalIntent.self, provider: GoalProvider()) { entry in
            GoalWidgetView(entry: entry)
                .levelUpWidgetBackground()
        }
        .configurationDisplayName("Цель")
        .description("Прогресс цели и сколько осталось до срока.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct GoalWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var goal: WidgetSnapshot.GoalEntry? {
        let goals = entry.snapshot.goals
        if let selection = entry.selection, let chosen = goals.first(where: { $0.id.uuidString == selection }) {
            return chosen
        }
        return goals.first
    }

    var body: some View {
        Group {
            if family == .accessoryCircular {
                Gauge(value: goal?.progress ?? 0) {
                    Image(systemName: "flag.fill")
                } currentValueLabel: {
                    Text(goal?.progress ?? 0, format: .percent.precision(.fractionLength(0)))
                }
                .gaugeStyle(.accessoryCircularCapacity)
            } else if !entry.snapshot.isSignedIn {
                WidgetUnavailableView(entry: entry)
            } else if let goal {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        ZStack {
                            Circle().stroke(Brand.accent.opacity(0.15), lineWidth: 7)
                            Circle()
                                .trim(from: 0, to: goal.progress)
                                .stroke(Brand.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .widgetAccentable()
                            Text(goal.progress, format: .percent.precision(.fractionLength(0)))
                                .font(.caption.bold().monospacedDigit())
                        }
                        .frame(width: 54, height: 54)
                        Spacer()
                        if let icon = goal.icon {
                            Text(verbatim: icon)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(goal.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if let deadline = goal.deadline {
                        let days = Calendar.current.dateComponents([.day], from: entry.day.date(), to: deadline.date()).day ?? 0
                        Text(days >= 0 ? String(localized: "Осталось \(days) дн.") : String(localized: "Срок прошёл"))
                            .font(.caption2)
                            .foregroundStyle(days < 0 ? .red : .secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(title: "Цель", systemImage: "flag.fill")
                    Spacer(minLength: 0)
                    Text("Целей пока нет")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .widgetURL(goal.map { AppRoute.goal($0.id).url } ?? AppRoute.goals.url)
    }
}

// MARK: - Кнопки Пункта управления

struct ExpenseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ExpenseControl") {
            ControlWidgetButton(action: OpenExpenseCaptureIntent()) {
                Label("Трата", systemImage: "creditcard.fill")
            }
        }
        .displayName("Трата")
        .description("Открывает Level Up и сразу слушает: «такси 3500».")
    }
}

struct WorkoutControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "WorkoutControl") {
            ControlWidgetButton(action: OpenWorkoutIntent()) {
                Label("Тренировка", systemImage: "figure.strengthtraining.traditional")
            }
        }
        .displayName("Тренировка")
        .description("Начать или продолжить тренировку.")
    }
}

#Preview(as: .systemSmall) {
    FinanceWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}

#Preview(as: .systemMedium) {
    QuestsWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}
