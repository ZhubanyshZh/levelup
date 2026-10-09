import LevelUpKit
import SwiftUI

/// Карточка одной записи в предпросмотре. Всё, что понял ИИ, можно поправить.
struct CaptureItemCard: View {
    @Binding var item: CaptureItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    if let kind = item.kind {
                        Text(kind.title)
                    } else {
                        Text("Запись")
                    }
                } icon: {
                    Image(systemName: item.kind?.symbol ?? "tray")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                Spacer()
                Button {
                    item.include.toggle()
                } label: {
                    Image(systemName: item.include ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.include ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.include ? Text("Не сохранять") : Text("Сохранить"))
            }

            TextField("Название", text: $item.title, axis: .vertical)
                .font(.body.weight(.medium))

            if let details = item.details {
                Text(details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            switch item.kind {
            case .task:
                TaskFields(item: $item)
                if let recurrence = item.recurrence {
                    HStack {
                        Label(recurrence.summary, systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        Button {
                            item.recurrence = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Без повтора"))
                    }
                    .font(.footnote)
                }
            case .profileFact:
                FactFields(item: item)
            case .journal:
                MoodPicker(mood: $item.mood)
                if !item.tags.isEmpty {
                    Text(item.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .shopping:
                ShoppingFields(item: $item)
            case .expense, .income:
                MoneyFields(item: $item)
            case .workout:
                WorkoutFields(item: $item)
            case .goal:
                GoalFields(item: item)
            default:
                Label("Этот раздел появится позже — запись подождёт во «Входящих».", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if item.kind == .task, let conflict = item.conflict {
                ConflictBanner(conflict: conflict) {
                    item.dueTime = conflict.end
                    item.conflict = nil
                }
            }
        }
        .opacity(item.include ? 1 : 0.45)
        .animation(.default, value: item.include)
    }
}

private struct TaskFields: View {
    @Binding var item: CaptureItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let dueDate = item.dueDate {
                    DatePicker(
                        "Дата",
                        selection: Binding(get: { dueDate.date() }, set: { item.dueDate = LocalDate($0) }),
                        displayedComponents: .date
                    )
                    .labelsHidden()

                    if let time = TimeText.date(from: item.dueTime) {
                        DatePicker(
                            "Время",
                            selection: Binding(get: { time }, set: {
                                item.dueTime = TimeText.string(from: $0)
                                item.conflict = nil
                            }),
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    } else {
                        Button("+ Время") { item.dueTime = "09:00" }
                            .buttonStyle(.bordered)
                    }

                    Button {
                        item.dueDate = nil
                        item.dueTime = nil
                        item.remind = false
                        item.conflict = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Убрать срок"))
                } else {
                    Button("+ Срок") { item.dueDate = .today() }
                        .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 8) {
                Toggle(isOn: $item.remind) {
                    Label("Напомнить", systemImage: item.remind ? "bell.fill" : "bell")
                }
                .toggleStyle(.button)
                .disabled(item.dueDate == nil)

                Menu {
                    Picker("Приоритет", selection: $item.priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label {
                        Text(item.priority.title)
                    } icon: {
                        Image(systemName: item.priority == .high ? "exclamationmark.circle.fill" : "flag")
                    }
                }
                .buttonStyle(.bordered)
            }
            .font(.footnote)
        }
    }
}

private struct FactFields: View {
    let item: CaptureItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let category = item.factCategory {
                Label(category.title, systemImage: category.symbol)
            }
            if let schedule = item.schedule {
                Label(schedule.summary, systemImage: "clock")
            }
            Text("ИИ будет учитывать это при планировании.")
                .foregroundStyle(.tertiary)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

private struct ConflictBanner: View {
    let conflict: BusyConflict
    let onReschedule: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Пересекается: «\(conflict.factText)» \(conflict.start)–\(conflict.end)", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
            Button("Перенести на \(conflict.end)", action: onReschedule)
                .buttonStyle(.bordered)
                .font(.footnote)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 10))
    }
}

private struct ShoppingFields: View {
    @Binding var item: CaptureItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let listName = item.listName {
                Label(listName, systemImage: "list.bullet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(item.products.indices, id: \.self) { index in
                HStack {
                    Image(systemName: "cart")
                        .foregroundStyle(.secondary)
                    Text(item.products[index].name)
                    if let quantity = item.products[index].quantity {
                        Text(quantity)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        item.products.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Убрать из списка"))
                }
                .font(.subheadline)
            }
        }
    }
}

private struct MoneyFields: View {
    @Binding var item: CaptureItem
    @Environment(AppStore.self) private var store

    private var categories: [MoneyCategory] {
        item.kind == .income ? MoneyCategory.incomes : MoneyCategory.expenses
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Сумма", value: $item.amount, format: .number)
                    .keyboardType(.decimalPad)
                    .font(.title3.bold())
                Text(verbatim: item.currency ?? store.finance.summary?.currency ?? "KZT")
                    .foregroundStyle(.secondary)
            }
            Menu {
                Picker("Категория", selection: Binding(
                    get: { MoneyCategory(rawValue: item.category ?? "") ?? categories.last! },
                    set: { item.category = $0.rawValue }
                )) {
                    ForEach(categories) { category in
                        Label(category.title, systemImage: category.symbol).tag(category)
                    }
                }
            } label: {
                CategoryLabel(key: item.category ?? categories.last!.rawValue)
                    .font(.footnote)
            }
            .buttonStyle(.bordered)
            if item.amount == nil {
                Text("Укажи сумму — без неё трата подождёт во «Входящих».")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct WorkoutFields: View {
    @Binding var item: CaptureItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(item.exercises.indices, id: \.self) { index in
                let exercise = item.exercises[index]
                HStack {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(exercise.name)
                        Text(summary(exercise))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        item.exercises.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Убрать упражнение"))
                }
                .font(.subheadline)
            }
            if item.exercises.isEmpty {
                Text("Упражнения не распознаны — запись подождёт во «Входящих».")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func summary(_ exercise: ExerciseEntry) -> String {
        let set = WorkoutFormat.set(SetInput(exercise: exercise.name, weightKg: exercise.weightKg, reps: exercise.reps, durationSec: exercise.durationSec, distanceM: exercise.distanceM))
        return exercise.sets > 1 ? String(localized: "\(exercise.sets) подх. · \(set)") : set
    }
}

private struct GoalFields: View {
    let item: CaptureItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let target = item.targetValue {
                let number = target.formatted(.number.precision(.fractionLength(0...2)))
                Label(item.metricUnit.map { "\(number) \($0)" } ?? number, systemImage: "target")
            }
            if let deadline = item.dueDate {
                Label(deadline.date().formatted(date: .long, time: .omitted), systemImage: "calendar")
            }
            Text("Шаг к цели — 100 XP, цель достигнута — 500 XP.")
                .foregroundStyle(.tertiary)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
