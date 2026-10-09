import LevelUpKit
import SwiftUI

struct GoalsView: View {
    @Environment(AppStore.self) private var store
    @State private var isCreating = false

    var body: some View {
        @Bindable var goals = store.goals
        List {
            if !goals.active.isEmpty {
                Section {
                    ForEach(goals.active) { goal in
                        NavigationLink {
                            GoalDetailView(goalID: goal.id)
                        } label: {
                            GoalRow(goal: goal)
                        }
                    }
                } footer: {
                    Text("Шаг к цели — 100 XP (до трёх в день), цель достигнута — 500 XP.")
                }
            }
            if !goals.done.isEmpty {
                Section("Достигнуты") {
                    ForEach(goals.done) { goal in
                        NavigationLink {
                            GoalDetailView(goalID: goal.id)
                        } label: {
                            GoalRow(goal: goal)
                        }
                    }
                }
            }
        }
        .overlay {
            if goals.goals.isEmpty {
                ContentUnavailableView {
                    Label("Целей пока нет", systemImage: "flag")
                } description: {
                    Text("Скажи «к декабрю хочу пробежать 10 км» или добавь цель вручную.")
                } actions: {
                    Button("Добавить цель") { isCreating = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Цели")
        .toolbar {
            Button {
                isCreating = true
            } label: {
                Label("Новая цель", systemImage: "plus")
            }
        }
        .refreshable { await goals.load() }
        .task { await goals.load() }
        .sheet(isPresented: $isCreating) { GoalEditorView(goal: nil) }
        .overlay(alignment: .bottom) { ErrorBanner(message: $goals.errorMessage) }
    }
}

struct GoalRow: View {
    let goal: Goal
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            ProgressRing(fraction: goal.progress, lineWidth: 5)
                .frame(width: 40, height: 40)
                .overlay {
                    Text(goal.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title)
                    .strikethrough(goal.isDone)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let sphere = store.progress.sphere(goal.sphere) {
                        Text(verbatim: "\(sphere.icon) \(sphere.name)")
                    }
                    if let days = goal.daysLeft(), !goal.isDone {
                        Text(days >= 0 ? String(localized: "Осталось \(days) дн.") : String(localized: "Срок прошёл"))
                            .foregroundStyle(days < 0 ? .red : .secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(.fill.tertiary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut, value: fraction)
        }
    }
}

// MARK: - Цель

struct GoalDetailView: View {
    let goalID: UUID

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var newStep = ""
    @State private var newValue: Double?
    @State private var isEditing = false
    @State private var confirmDelete = false

    var body: some View {
        if let goal = store.goals.goal(goalID) {
            content(goal)
        } else {
            ContentUnavailableView("Цель удалена", systemImage: "flag.slash")
        }
    }

    private func content(_ goal: Goal) -> some View {
        List {
            Section {
                VStack(spacing: 12) {
                    ProgressRing(fraction: goal.progress, lineWidth: 12)
                        .frame(width: 130, height: 130)
                        .overlay {
                            Text(goal.progress, format: .percent.precision(.fractionLength(0)))
                                .font(.title.bold().monospacedDigit())
                        }
                    if let why = goal.why {
                        Text(why)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if let deadline = goal.deadline {
                        Label(deadline.date().formatted(date: .long, time: .omitted), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle((goal.daysLeft() ?? 0) < 0 && !goal.isDone ? .red : .secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            if goal.hasMetric {
                Section("Прогресс") {
                    LabeledContent("Сейчас", value: metric(goal.currentValue ?? goal.startValue ?? 0, unit: goal.metricUnit))
                    LabeledContent("Цель", value: metric(goal.targetValue ?? 0, unit: goal.metricUnit))
                    if !goal.isDone {
                        HStack {
                            TextField("Новое значение", value: $newValue, format: .number)
                                .keyboardType(.decimalPad)
                            Button("Обновить") {
                                var updated = goal
                                updated.currentValue = newValue
                                newValue = nil
                                Task { _ = await store.goals.save(updated) }
                            }
                            .disabled(newValue == nil)
                        }
                    }
                }
            }

            Section("Шаги") {
                ForEach(goal.steps) { step in
                    Button {
                        Task { await store.goals.toggle(step, in: goal) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(step.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                .font(.title3)
                            Text(step.title)
                                .strikethrough(step.isDone)
                                .foregroundStyle(step.isDone ? .secondary : .primary)
                            Spacer()
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Удалить", systemImage: "trash", role: .destructive) {
                            Task { await store.goals.deleteStep(step, in: goal) }
                        }
                    }
                }
                HStack {
                    TextField("Новый шаг", text: $newStep)
                        .onSubmit { addStep(goal) }
                    Button {
                        addStep(goal)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newStep.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            let tasks = store.tasks.tasks.filter { $0.goalId == goal.id }
            if !tasks.isEmpty {
                Section("Задачи") {
                    ForEach(tasks) { task in
                        TaskRow(task: task) {
                            Task { await store.tasks.toggleDone(task) }
                        }
                    }
                }
            }

            Section {
                if goal.isDone {
                    Button("Вернуть в работу") { setStatus(.active, goal) }
                } else {
                    Button {
                        setStatus(.done, goal)
                    } label: {
                        Label("Цель достигнута", systemImage: "flag.checkered")
                    }
                }
                Button("Удалить цель", role: .destructive) { confirmDelete = true }
            } footer: {
                if !goal.isDone {
                    Text("За достигнутую цель — 500 XP (если цели больше суток).")
                }
            }
        }
        .navigationTitle(goal.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Изменить") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) { GoalEditorView(goal: goal) }
        .confirmationDialog("Удалить цель?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                Task {
                    await store.goals.delete(goal)
                    dismiss()
                }
            }
        }
        .sensoryFeedback(.success, trigger: goal.steps.filter(\.isDone).count)
    }

    private func metric(_ value: Double, unit: String?) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        return unit.map { "\(number) \($0)" } ?? number
    }

    private func addStep(_ goal: Goal) {
        let title = newStep
        newStep = ""
        Task { await store.goals.addStep(to: goal, title: title) }
    }

    private func setStatus(_ status: GoalStatus, _ goal: Goal) {
        var updated = goal
        updated.status = status
        Task { _ = await store.goals.save(updated) }
    }
}

// MARK: - Редактор

struct GoalEditorView: View {
    let goal: Goal?

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var why = ""
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now
    @State private var hasMetric = false
    @State private var unit = ""
    @State private var start: Double?
    @State private var target: Double?
    @State private var sphere: String?
    @State private var steps = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Чего хочешь добиться", text: $title, axis: .vertical)
                        .font(.body.weight(.medium))
                    TextField("Зачем это тебе", text: $why, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Toggle("Срок", isOn: $hasDeadline.animation())
                    if hasDeadline {
                        DatePicker("Срок", selection: $deadline, in: Date.now..., displayedComponents: .date)
                    }
                    SpherePicker(selection: $sphere)
                }
                Section {
                    Toggle("Измеримая цель", isOn: $hasMetric.animation())
                    if hasMetric {
                        TextField("Единица: км, кг, книг…", text: $unit)
                        TextField("Сейчас", value: $start, format: .number)
                            .keyboardType(.decimalPad)
                        TextField("Цель", value: $target, format: .number)
                            .keyboardType(.decimalPad)
                    }
                } footer: {
                    Text("Без числа прогресс считается по шагам.")
                }
                if goal == nil {
                    Section {
                        TextField("По одному на строке", text: $steps, axis: .vertical)
                            .lineLimit(3...8)
                    } header: {
                        Text("Шаги")
                    }
                }
            }
            .navigationTitle(goal == nil ? "Новая цель" : "Цель")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving || (hasMetric && target == nil))
                }
            }
            .onAppear(perform: fill)
        }
    }

    private func fill() {
        guard let goal else { return }
        title = goal.title
        why = goal.why ?? ""
        hasDeadline = goal.deadline != nil
        deadline = goal.deadline?.date() ?? deadline
        hasMetric = goal.hasMetric
        unit = goal.metricUnit ?? ""
        start = goal.currentValue ?? goal.startValue
        target = goal.targetValue
        sphere = goal.sphere
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmedWhy = why.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        if var updated = goal {
            updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.why = trimmedWhy.isEmpty ? nil : trimmedWhy
            updated.deadline = hasDeadline ? LocalDate(deadline) : nil
            updated.metricUnit = hasMetric && !trimmedUnit.isEmpty ? trimmedUnit : nil
            updated.targetValue = hasMetric ? target : nil
            if hasMetric {
                if updated.startValue == nil { updated.startValue = start ?? 0 }
                updated.currentValue = start
            } else {
                updated.startValue = nil
                updated.currentValue = nil
            }
            updated.sphere = sphere
            if await store.goals.save(updated) { dismiss() }
        } else {
            let input = GoalInput(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                why: trimmedWhy.isEmpty ? nil : trimmedWhy,
                deadline: hasDeadline ? LocalDate(deadline) : nil,
                metricUnit: hasMetric && !trimmedUnit.isEmpty ? trimmedUnit : nil,
                startValue: hasMetric ? (start ?? 0) : nil,
                currentValue: hasMetric ? (start ?? 0) : nil,
                targetValue: hasMetric ? target : nil,
                sphere: sphere,
                steps: steps.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            )
            if await store.goals.create(input) != nil { dismiss() }
        }
    }
}

/// Выбор сферы жизни (для задач и целей).
struct SpherePicker: View {
    @Binding var selection: String?
    @Environment(AppStore.self) private var store

    var body: some View {
        Picker("Сфера", selection: $selection) {
            Text("Не выбрана").tag(String?.none)
            ForEach(store.progress.progress.spheres) { sphere in
                Text(verbatim: "\(sphere.icon) \(sphere.name)").tag(Optional(sphere.key))
            }
        }
    }
}
