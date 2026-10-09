import LevelUpKit
import SwiftUI

/// Создание и редактирование задачи вручную.
struct TaskEditorView: View {
    let task: TaskItem?

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var status: TaskStatus = .todo
    @State private var priority: TaskPriority = .normal
    @State private var hasDate = false
    @State private var date = Date.now
    @State private var hasTime = false
    @State private var time = TimeText.date(from: "09:00") ?? .now
    @State private var remind = false
    @State private var difficulty = 0
    @State private var repeatFrequency: Recurrence.Frequency?
    @State private var repeatDays: Set<Weekday> = []
    @State private var sphere: String?
    @State private var goalID: UUID?
    @State private var isSaving = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Что сделать", text: $title, axis: .vertical)
                        .font(.body.weight(.medium))
                    TextField("Заметка", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section {
                    Picker("Статус", selection: $status) {
                        ForEach(TaskStatus.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Приоритет", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }

                Section("Срок") {
                    Toggle("Дата", isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker("Дата", selection: $date, displayedComponents: .date)
                        Toggle("Время", isOn: $hasTime.animation())
                        if hasTime {
                            DatePicker("Время", selection: $time, displayedComponents: .hourAndMinute)
                        }
                        Toggle("Напомнить", isOn: $remind)
                    }
                }

                Section {
                    Picker("Повтор", selection: $repeatFrequency.animation()) {
                        Text("Нет").tag(Recurrence.Frequency?.none)
                        ForEach(Recurrence.Frequency.allCases, id: \.self) { frequency in
                            Text(frequency.title).tag(Optional(frequency))
                        }
                    }
                    if repeatFrequency == .weekly {
                        WeekdayPicker(selection: $repeatDays)
                    }
                } footer: {
                    if repeatFrequency != nil {
                        Text("Выполненная повторяющаяся задача переезжает на следующий раз.")
                    }
                }

                Section {
                    Picker("Сложность", selection: $difficulty) {
                        Text("—").tag(0)
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Сложность")
                } footer: {
                    Text("1 — пара минут, 5 — несколько дней. Пригодится для опыта (XP).")
                }

                Section {
                    SpherePicker(selection: $sphere)
                    if !store.goals.active.isEmpty || goalID != nil {
                        Picker("Цель", selection: $goalID) {
                            Text("Без цели").tag(UUID?.none)
                            ForEach(store.goals.goals.filter { !$0.isDone || $0.id == goalID }) { goal in
                                Text(goal.title).tag(Optional(goal.id))
                            }
                        }
                    }
                } footer: {
                    Text("Опыт за задачу пойдёт в эту сферу.")
                }

                if task != nil {
                    Section {
                        Button("Удалить задачу", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(task == nil ? "Новая задача" : "Задача")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .confirmationDialog("Удалить задачу?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    guard let task else { return }
                    Task {
                        await store.tasks.delete(task)
                        dismiss()
                    }
                }
            }
            .onAppear(perform: fill)
        }
    }

    private func fill() {
        guard let task else { return }
        title = task.title
        notes = task.notes ?? ""
        status = task.status
        priority = task.priority
        hasDate = task.dueDate != nil
        date = task.dueDate?.date() ?? .now
        hasTime = task.dueTime != nil
        time = TimeText.date(from: task.dueTime) ?? time
        remind = task.remind
        difficulty = task.difficulty ?? 0
        repeatFrequency = task.recurrence?.freq
        repeatDays = Set(task.recurrence?.weekdays ?? [])
        sphere = task.sphere
        goalID = task.goalId
    }

    private var recurrence: Recurrence? {
        repeatFrequency.map { Recurrence(freq: $0, weekdays: $0 == .weekly ? repeatDays.sorted() : []) }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let dueDate = hasDate ? LocalDate(date) : nil
        let dueTime = hasDate && hasTime ? TimeText.string(from: time) : nil

        if var updated = task {
            updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            updated.status = status
            updated.priority = priority
            updated.dueDate = dueDate
            updated.dueTime = dueTime
            updated.remind = hasDate && remind
            updated.difficulty = difficulty == 0 ? nil : difficulty
            updated.recurrence = recurrence
            updated.sphere = sphere
            updated.goalId = goalID
            await store.tasks.save(updated)
            dismiss()
        } else {
            let draft = TaskDraft(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                status: status,
                priority: priority,
                dueDate: dueDate,
                dueTime: dueTime,
                remind: hasDate && remind,
                difficulty: difficulty == 0 ? nil : difficulty,
                recurrence: recurrence,
                sphere: sphere,
                goalId: goalID
            )
            if await store.tasks.create(draft) {
                dismiss()
            }
        }
    }
}
