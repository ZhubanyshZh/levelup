import LevelUpKit
import SwiftUI

struct JournalView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: JournalEntry?
    @State private var isCreating = false

    var body: some View {
        @Bindable var journal = store.journal
        NavigationStack {
            List {
                Section {
                    MoodStrip(days: journal.moodByDay(last: 14))
                } header: {
                    Text("Настроение за 2 недели")
                }

                if !journal.hasEntryToday {
                    Section {
                        Button {
                            isCreating = true
                        } label: {
                            Label("Как проходит день? Пара слов — и +15 XP", systemImage: "square.and.pencil")
                        }
                    }
                }

                ForEach(journal.groupedByDay) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            JournalRow(entry: entry)
                                .contentShape(.rect)
                                .onTapGesture { editing = entry }
                                .swipeActions {
                                    Button("Удалить", systemImage: "trash", role: .destructive) {
                                        Task { await journal.delete(entry) }
                                    }
                                }
                        }
                    } header: {
                        Text(DueFormat.label(date: group.date, time: nil) ?? "")
                    }
                }
            }
            .overlay {
                if journal.entries.isEmpty {
                    ContentUnavailableView(
                        "Дневник пуст",
                        systemImage: "book",
                        description: Text("Расскажи, как прошёл день, — голосом через «Записать» или кнопкой «+».")
                    )
                }
            }
            .navigationTitle("Дневник")
            .toolbar {
                Button {
                    isCreating = true
                } label: {
                    Label("Новая запись", systemImage: "plus")
                }
            }
            .refreshable { await journal.load() }
            .sheet(item: $editing) { JournalEditorView(entry: $0) }
            .sheet(isPresented: $isCreating) { JournalEditorView(entry: nil) }
            .overlay(alignment: .bottom) { ErrorBanner(message: $journal.errorMessage) }
        }
    }
}

private struct JournalRow: View {
    let entry: JournalEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.mood.map(Mood.emoji) ?? "📝")
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                if let summary = entry.summary {
                    Text(summary)
                        .font(.body.weight(.medium))
                    Text(entry.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(entry.text)
                        .lineLimit(4)
                }
                HStack(spacing: 6) {
                    Text(entry.createdAt, format: .dateTime.hour().minute())
                    if let energy = entry.energy {
                        Image(systemName: Mood.batterySymbol(energy))
                    }
                    ForEach(entry.tags, id: \.self) { tag in
                        Text("#\(tag)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// Настроение по дням: цветной кружок со смайликом, пустой — день без оценки.
private struct MoodStrip: View {
    let days: [(date: LocalDate, mood: Int?)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(days, id: \.date) { day in
                        VStack(spacing: 4) {
                            Text(day.date.date().formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ZStack {
                                Circle()
                                    .fill(day.mood.map { Mood.color($0).opacity(0.3) } ?? Color.secondary.opacity(0.12))
                                Text(day.mood.map(Mood.emoji) ?? "")
                                    .font(.callout)
                            }
                            .frame(width: 34, height: 34)
                            Text(day.date.day, format: .number)
                                .font(.caption2)
                                .foregroundStyle(day.date == LocalDate.today() ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        }
                        .id(day.date)
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(days.last?.date, anchor: .trailing) }
        }
    }
}

struct JournalEditorView: View {
    let entry: JournalEntry?

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var text = ""
    @State private var mood: Int?
    @State private var energy: Int?
    @State private var tags = ""
    @State private var isSaving = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Дата", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
                Section {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $text)
                            .frame(minHeight: 160)
                        if text.isEmpty {
                            Text("Что было сегодня? Что получилось, что нет, что чувствуешь?")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                }
                Section("Настроение") {
                    MoodPicker(mood: $mood)
                }
                Section("Энергия") {
                    EnergyPicker(energy: $energy)
                }
                Section {
                    TextField("работа, спорт, семья", text: $tags)
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Теги")
                } footer: {
                    Text("Через запятую.")
                }
                if entry != nil {
                    Section {
                        Button("Удалить запись", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(entry == nil ? "Новая запись" : "Запись")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .confirmationDialog("Удалить запись?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    guard let entry else { return }
                    Task {
                        await store.journal.delete(entry)
                        dismiss()
                    }
                }
            }
            .onAppear(perform: fill)
        }
    }

    private func fill() {
        guard let entry else { return }
        date = entry.entryDate.date()
        text = entry.text
        mood = entry.mood
        energy = entry.energy
        tags = entry.tags.joined(separator: ", ")
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let input = JournalInput(
            entryDate: LocalDate(date),
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            mood: mood,
            energy: energy,
            tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        )
        let saved = if let entry {
            await store.journal.update(entry, with: input)
        } else {
            await store.journal.create(input)
        }
        if saved {
            dismiss()
        }
    }
}
