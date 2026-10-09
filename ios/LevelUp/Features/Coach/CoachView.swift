import LevelUpKit
import SwiftUI

extension CoachKind {
    var title: String {
        switch self {
        case .morning: String(localized: "Утренний план")
        case .evening: String(localized: "Вечерний вопрос")
        case .weekly: String(localized: "Обзор недели")
        case .goal: String(localized: "Шаги к цели")
        }
    }
}

struct CoachView: View {
    @Environment(AppStore.self) private var store
    @State private var kind: CoachKind
    init(kind: CoachKind = .current()) { _kind = State(initialValue: kind) }
    @AppStorage("coachAutomatic") private var automatic = false
    @AppStorage("coachReminders") private var reminders = false

    var body: some View {
        @Bindable var coach = store.coach
        List {
            Section {
                Picker("Режим коуча", selection: $kind) {
                    ForEach([CoachKind.morning, .evening, .weekly], id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
            if store.ai.settings?.activeProvider == nil {
                Section {
                    Text("Для коуча нужен ключ ИИ-провайдера.").foregroundStyle(.secondary)
                    NavigationLink { AISettingsView() } label: { Label("Настроить ИИ", systemImage: "key") }
                }
            }
            if let report = coach.report(kind) {
                CoachReportSections(report: report)
            } else {
                Section {
                    Text("Коуч учтёт задачи, цели и факты из «Обо мне».")
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await coach.generate(kind) }
                    } label: {
                        HStack {
                            Label("Подготовить", systemImage: "sparkles")
                            if coach.generating.contains(kind) { Spacer(); ProgressView() }
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(coach.generating.contains(kind) || store.ai.settings?.activeProvider == nil)
                } header: { Text(kind.title) } footer: {
                    Text("Запрос использует твой ключ ИИ. Готовый план сохраняется; повторное открытие не тратит квоту.")
                }
            }
            Section {
                NavigationLink { CoachQuestionView() } label: {
                    Label("Спросить о своих данных", systemImage: "questionmark.bubble")
                }
                NavigationLink { CoachHistoryView() } label: {
                    Label("История коуча", systemImage: "clock.arrow.circlepath")
                }
            }
            Section {
                Toggle("Готовить при открытии приложения", isOn: $automatic)
                Toggle("Напоминания коуча", isOn: $reminders)
                    .onChange(of: reminders) { _, enabled in
                        Task {
                            let allowed = await store.configureCoachReminders(enabled)
                            if enabled && !allowed { reminders = false }
                        }
                    }
            } header: { Text("Ритм") } footer: {
                Text("План утром, вопрос вечером, обзор по понедельникам. Напоминания локальные; время сдвигается в обход занятости. ИИ отвечает при открытии приложения.")
            }
        }
        .navigationTitle("ИИ-коуч")
        .refreshable { await coach.load() }
        .task { await coach.load() }
        .overlay(alignment: .bottom) { ErrorBanner(message: $coach.errorMessage) }
    }
}

struct CoachGoalView: View {
    let goalID: UUID
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var coach = store.coach
        List {
            if let goal = store.goals.goal(goalID) {
                Section { Text(goal.title).font(.headline) }
            }
            if let report = coach.report(.goal, goalID: goalID) {
                CoachReportSections(report: report)
            }
            Section {
                Button {
                    Task { await coach.generate(.goal, goalID: goalID) }
                } label: {
                    HStack {
                        Label("Предложить шаги", systemImage: "sparkles")
                        if coach.generating.contains(.goal) { Spacer(); ProgressView() }
                    }
                    .frame(minHeight: 44)
                }
                .disabled(coach.generating.contains(.goal) || store.goals.goal(goalID)?.isDone != false)
            } footer: { Text("Шаги появятся в цели после принятия. Коуч учитывает уже добавленные шаги.") }
        }
        .navigationTitle("Шаги к цели")
        .task { await coach.load() }
        .overlay(alignment: .bottom) { ErrorBanner(message: $coach.errorMessage) }
    }
}

struct CoachReportSections: View {
    let report: CoachReport
    @Environment(AppStore.self) private var store
    @State private var isWriting = false

    private var current: CoachReport { store.coach.reports.first { $0.id == report.id } ?? report }

    var body: some View {
        Section {
            Text(current.title).font(.headline)
            Text(current.message).textSelection(.enabled)
            ForEach(Array(current.highlights.enumerated()), id: \.offset) { _, highlight in
                Label(highlight, systemImage: "circle.fill").font(.subheadline)
            }
        }
        if let question = current.reflectionQuestion, current.kind == .evening {
            Section {
                Text(question).font(.headline)
                Button { isWriting = true } label: { Label("Ответить в дневнике", systemImage: "square.and.pencil") }
                    .frame(minHeight: 44)
            }
            .sheet(isPresented: $isWriting) { JournalEditorView(entry: nil, prompt: question) }
        }
        if !current.actions.isEmpty {
            Section {
                ForEach(current.actions) { action in
                    CoachActionRow(action: action, report: current)
                }
            } header: { Text("Следующие шаги") } footer: {
                Text("Предложения применяются только после принятия. XP начисляется за выполненные действия.")
            }
        }
    }
}

private struct CoachActionRow: View {
    let action: CoachAction
    let report: CoachReport
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(action.title).font(.body.weight(.medium))
            if let notes = action.notes { Text(notes).font(.subheadline).foregroundStyle(.secondary) }
            if report.kind != .goal {
                HStack {
                    if let date = action.dueDate {
                        Text(DueFormat.label(date: date, time: action.dueTime) ?? "")
                    }
                    Text("~\(action.durationMinutes) мин.")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            if let conflict = action.conflict {
                Label(String(localized: "Занято: \(conflict.factText)"), systemImage: "calendar.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.orange)
            }
            if action.appliedId != nil {
                Label("Принято", systemImage: "checkmark.circle.fill").foregroundStyle(.tint)
            } else {
                HStack {
                    Button {
                        Task { await apply(unscheduled: action.conflict != nil) }
                    } label: {
                        Text(action.conflict != nil ? String(localized: "Добавить без времени") : report.kind == .goal ? String(localized: "Добавить шаг") : action.taskId != nil ? String(localized: "Применить расписание") : String(localized: "Добавить задачу"))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    if action.dueTime != nil && action.conflict == nil && report.kind != .goal {
                        Menu {
                            Button("Добавить без времени") { Task { await apply(unscheduled: true) } }
                        } label: {
                            Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Другие варианты принятия")
                    }
                    if store.coach.applying.contains(action.id) { ProgressView() }
                }
                .disabled(store.coach.applying.contains(action.id))
            }
        }
        .padding(.vertical, 6)
    }

    private func apply(unscheduled: Bool) async {
        guard let result = await store.coach.apply(action, in: report, unscheduled: unscheduled) else { return }
        if let task = result.task { store.tasks.insert([task]) }
        if let goal = result.goal { store.goals.insert([goal]) }
    }
}

struct CoachHistoryView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var coach = store.coach
        List {
            if !store.coach.answers.isEmpty {
                Section("Вопросы к данным") {
                    ForEach(store.coach.answers) { answer in
                        NavigationLink {
                            List { CoachAnswerSections(answer: answer) }.navigationTitle("Ответ коуча")
                        } label: { Text(answer.question).lineLimit(2) }
                    }
                }
            }
            Section("Планы и обзоры") {
                ForEach(store.coach.reports) { report in
                    NavigationLink {
                        List { CoachReportSections(report: report) }.navigationTitle(report.kind.title)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(report.title)
                            Text(report.periodStart.date(), format: .dateTime.day().month().year())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay {
            if store.coach.reports.isEmpty && store.coach.answers.isEmpty {
                ContentUnavailableView("История пока пуста", systemImage: "sparkles")
            }
        }
        .navigationTitle("История коуча")
        .overlay(alignment: .bottom) { ErrorBanner(message: $coach.errorMessage) }
    }
}
