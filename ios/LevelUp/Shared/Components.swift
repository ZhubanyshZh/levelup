import LevelUpKit
import SwiftUI

struct LevelCard: View {
    let progress: LevelProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Уровень \(progress.level)", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(.tint)
                Spacer()
                Text("\(progress.xpInLevel) / \(progress.xpForNextLevel) XP")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(progress.xpInLevel), total: Double(max(progress.xpForNextLevel, 1)))
            if progress.todayXp > 0 {
                Text("Сегодня +\(progress.todayXp) XP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Строка задачи: отметка «готово», название, срок и признаки.
struct TaskRow: View {
    let task: TaskItem
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? Text("Вернуть в работу") : Text("Отметить выполненной"))

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                TaskMeta(task: task)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}

struct TaskMeta: View {
    let task: TaskItem

    var body: some View {
        let due = DueFormat.label(date: task.dueDate, time: task.dueTime)
        if due != nil || task.remind || task.priority == .high || task.status == .doing {
            HStack(spacing: 8) {
                if task.priority == .high {
                    Label("Важно", systemImage: "exclamationmark")
                        .foregroundStyle(.orange)
                }
                if task.status == .doing {
                    Label("В работе", systemImage: "circle.lefthalf.filled")
                        .foregroundStyle(.tint)
                }
                if let due {
                    Label(due, systemImage: "calendar")
                        .foregroundStyle(DueFormat.isOverdue(task) ? .red : .secondary)
                }
                if task.recurrence != nil {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Повторяется"))
                }
                if task.remind && !task.isDone {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("С напоминанием"))
                }
            }
            .font(.caption)
            .labelStyle(.titleAndIcon)
        }
    }
}

/// Сообщение об ошибке, которое само исчезает по нажатию.
struct ErrorBanner: View {
    @Binding var message: String?

    var body: some View {
        if let message {
            Button {
                self.message = nil
            } label: {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.red.gradient, in: .capsule)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Weekday>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(day.shortTitle)
                        .font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary), in: .rect(cornerRadius: 8))
                        .foregroundStyle(isOn ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: day.title))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

extension View {
    /// Return закрывает однострочный ввод; «Готово» доступно и на цифровой клавиатуре.
    func keyboardDismissal(isFocused: Bool, dismiss: @escaping () -> Void) -> some View {
        scrollDismissesKeyboard(.interactively)
            .onSubmit(dismiss)
            .toolbar {
                if isFocused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Готово", action: dismiss)
                    }
                }
            }
    }
}

/// Настроение 1–5 смайликами. Повторное нажатие снимает выбор.
struct MoodPicker: View {
    @Binding var mood: Int?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    mood = mood == value ? nil : value
                } label: {
                    Text(Mood.emoji(value))
                        .font(.title2)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(
                            mood == value ? AnyShapeStyle(Mood.color(value).opacity(0.25)) : AnyShapeStyle(.clear),
                            in: .rect(cornerRadius: 10)
                        )
                        .opacity(mood == nil || mood == value ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(Mood.title(value)))
            }
        }
    }
}

/// Энергия 1–5 батарейками.
struct EnergyPicker: View {
    @Binding var energy: Int?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    energy = energy == value ? nil : value
                } label: {
                    Image(systemName: Mood.batterySymbol(value))
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(energy == value ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .opacity(energy == nil || energy == value ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Энергия \(value) из 5"))
            }
        }
    }
}
