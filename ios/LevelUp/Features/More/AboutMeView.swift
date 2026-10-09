import LevelUpKit
import SwiftUI

/// «Обо мне»: то, что ИИ учитывает при каждом разборе и планировании.
struct AboutMeView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: ProfileFact?
    @State private var isCreating = false

    var body: some View {
        @Bindable var profile = store.profile
        List {
            Section {
                Text("ИИ учитывает это при каждой записи. Факт можно добавить и голосом: «Запомни, что по пятницам с 12:30 до 14:00 у меня жума».")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(FactCategory.allCases, id: \.self) { category in
                let facts = profile.facts(in: category)
                if !facts.isEmpty {
                    Section {
                        ForEach(facts) { fact in
                            FactRow(fact: fact)
                                .contentShape(.rect)
                                .onTapGesture { editing = fact }
                                .swipeActions {
                                    Button("Удалить", systemImage: "trash", role: .destructive) {
                                        Task { await profile.delete(fact) }
                                    }
                                }
                        }
                    } header: {
                        Label(category.title, systemImage: category.symbol)
                    }
                }
            }
        }
        .overlay {
            if profile.facts.isEmpty {
                ContentUnavailableView(
                    "Пока ничего",
                    systemImage: "person.text.rectangle",
                    description: Text("Расскажи о своём распорядке и привычках — планы станут точнее.")
                )
            }
        }
        .navigationTitle("Обо мне")
        .toolbar {
            Button {
                isCreating = true
            } label: {
                Label("Добавить", systemImage: "plus")
            }
        }
        .sheet(item: $editing) { FactEditorView(fact: $0) }
        .sheet(isPresented: $isCreating) { FactEditorView(fact: nil) }
        .overlay(alignment: .bottom) { ErrorBanner(message: $profile.errorMessage) }
        .task { await profile.load() }
    }
}

private struct FactRow: View {
    let fact: ProfileFact
    @Environment(AppStore.self) private var store

    var body: some View {
        Toggle(isOn: Binding(
            get: { fact.isActive },
            set: { isActive in Task { await store.profile.setActive(fact, isActive) } }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Text(fact.text)
                    .foregroundStyle(fact.isActive ? .primary : .secondary)
                if let schedule = fact.schedule {
                    Text(schedule.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct FactEditorView: View {
    let fact: ProfileFact?

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var category: FactCategory = .schedule
    @State private var text = ""
    @State private var hasSchedule = false
    @State private var weekdays: Set<Weekday> = []
    @State private var start = TimeText.date(from: "09:00") ?? .now
    @State private var end = TimeText.date(from: "18:00") ?? .now
    @State private var busy = true
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Например: работаю с 9 до 18", text: $text, axis: .vertical)
                    Picker("Раздел", selection: $category) {
                        ForEach(FactCategory.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    Toggle("Регулярное время", isOn: $hasSchedule.animation())
                    if hasSchedule {
                        WeekdayPicker(selection: $weekdays)
                        DatePicker("С", selection: $start, displayedComponents: .hourAndMinute)
                        DatePicker("До", selection: $end, displayedComponents: .hourAndMinute)
                        Toggle("В это время я занят", isOn: $busy)
                    }
                } footer: {
                    if hasSchedule && busy {
                        Text("Задачи на это время ИИ будет отмечать как пересечение.")
                    }
                }
            }
            .navigationTitle(fact == nil ? "Новый факт" : "Факт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                        .disabled(!isValid || isSaving)
                }
            }
            .onAppear(perform: fill)
        }
    }

    private var isValid: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let scheduleOK = !hasSchedule || (!weekdays.isEmpty && TimeText.string(from: start) != TimeText.string(from: end))
        return hasText && scheduleOK
    }

    private func fill() {
        guard let fact else { return }
        category = fact.category
        text = fact.text
        if let schedule = fact.schedule {
            hasSchedule = true
            weekdays = Set(schedule.weekdays)
            start = TimeText.date(from: schedule.start) ?? start
            end = TimeText.date(from: schedule.end) ?? end
            busy = schedule.busy
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let schedule = hasSchedule
            ? Schedule(weekdays: weekdays.sorted(), start: TimeText.string(from: start), end: TimeText.string(from: end), busy: busy)
            : nil
        let input = FactInput(
            category: category,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            schedule: schedule,
            isActive: fact?.isActive ?? true
        )
        let saved = if let fact {
            await store.profile.update(fact, with: input)
        } else {
            await store.profile.create(input)
        }
        if saved {
            dismiss()
        }
    }
}
