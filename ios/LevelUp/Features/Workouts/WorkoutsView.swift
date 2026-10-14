import Charts
import LevelUpKit
import SwiftUI

struct WorkoutsView: View {
    @Environment(AppStore.self) private var store
    @State private var isTraining = false

    var body: some View {
        @Bindable var workouts = store.workouts
        List {
            Section {
                Button {
                    if workouts.active == nil { workouts.start() }
                    isTraining = true
                } label: {
                    Label(workouts.active == nil ? "Начать тренировку" : "Продолжить тренировку", systemImage: workouts.active == nil ? "play.fill" : "figure.strengthtraining.traditional")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            } footer: {
                Text("Тренировка — 25 XP, личный рекорд — ещё +50. Можно и голосом: «жим 3 по 5 с 80».")
            }

            Section {
                LabeledContent("На этой неделе") {
                    Text(workouts.thisWeek.count, format: .number)
                }
            }

            if !workouts.exercises.isEmpty {
                Section("Упражнения") {
                    ForEach(workouts.exercises.prefix(8)) { stats in
                        NavigationLink {
                            ExerciseDetailView(stats: stats)
                        } label: {
                            ExerciseRow(stats: stats)
                        }
                    }
                }
            }

            if !workouts.workouts.isEmpty {
                Section("История") {
                    ForEach(workouts.workouts) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            WorkoutRow(workout: workout)
                        }
                        .swipeActions {
                            Button("Удалить", systemImage: "trash", role: .destructive) {
                                Task { await workouts.delete(workout) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Тренировки")
        .refreshable { await workouts.load() }
        .task { await workouts.load() }
        .fullScreenCover(isPresented: $isTraining) {
            ActiveWorkoutView()
        }
        .overlay(alignment: .bottom) { ErrorBanner(message: $workouts.errorMessage) }
    }
}

private struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(workout.title ?? workout.exercises.map(\.name).prefix(3).joined(separator: ", "))
                    .lineLimit(1)
                if workout.hasRecord {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityLabel(Text("Личный рекорд"))
                }
            }
            HStack(spacing: 8) {
                Text(DueFormat.label(date: workout.workoutDate, time: nil) ?? "")
                Text("Подходов: \(workout.sets.count)")
                if let duration = workout.duration {
                    Text(Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct ExerciseRow: View {
    let stats: ExerciseStats

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(stats.name)
                Text("Занятий: \(stats.sessions)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let best = stats.bestLabel {
                Label(best, systemImage: "trophy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension ExerciseStats {
    /// Лучший результат: вес, повторы, время или дистанция.
    var bestLabel: String? {
        if let weight = bestWeightKg {
            return String(localized: "\(weight.formatted(.number.precision(.fractionLength(0...1)))) кг")
        }
        if let reps = bestReps { return String(localized: "\(reps) повт.") }
        if let seconds = bestDurationSec { return WorkoutFormat.duration(seconds) }
        if let meters = bestDistanceM { return WorkoutFormat.distance(meters) }
        return nil
    }
}

// MARK: - Тренировка в процессе

struct ActiveWorkoutView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var exercise = ""
    @State private var weight: Double?
    @State private var reps: Int?
    @State private var minutes: Int?
    @State private var kilometers: Double?
    @State private var showsMore = false
    @State private var isFinishing = false
    @State private var confirmCancel = false
    @FocusState private var focusedField: WorkoutInputField?

    var body: some View {
        let workouts = store.workouts
        NavigationStack {
            Group {
                if let active = workouts.active {
                    content(active)
                } else if let result = workouts.lastResult {
                    WorkoutResultView(result: result) {
                        workouts.lastResult = nil
                        dismiss()
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(workouts.active != nil)
    }

    private func content(_ active: ActiveWorkout) -> some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Идёт")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(active.startedAt, style: .timer)
                            .font(.title.monospacedDigit().bold())
                    }
                    Spacer()
                    if let restEnds = active.restEndsAt, restEnds > .now {
                        RestTimer(endsAt: restEnds)
                    }
                }
            }

            Section {
                TextField("Упражнение", text: $exercise)
                    .focused($focusedField, equals: .exercise)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .onSubmit(selectExercise)
                if focusedField == .exercise || exercise.isEmpty {
                    SuggestionStrip(names: suggestions) { name in
                        exercise = name
                        selectExercise()
                    }
                }
                HStack {
                    NumberField("Вес, кг", value: $weight, focus: $focusedField, field: .weight)
                    NumberField("Повторы", value: Binding(get: { reps.map(Double.init) }, set: { reps = $0.map { Int($0) } }), focus: $focusedField, field: .reps)
                }
                if showsMore {
                    HStack {
                        NumberField("Минуты", value: Binding(get: { minutes.map(Double.init) }, set: { minutes = $0.map { Int($0) } }), focus: $focusedField, field: .minutes)
                        NumberField("Км", value: $kilometers, focus: $focusedField, field: .kilometers)
                    }
                } else {
                    Button("Время или дистанция") { showsMore = true }
                        .font(.footnote)
                }
                Button {
                    addSet()
                } label: {
                    Label("Подход ✓", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAddSet)
            }

            if !active.sets.isEmpty {
                Section("Подходы") {
                    ForEach(Array(active.sets.enumerated().reversed()), id: \.offset) { index, set in
                        HStack {
                            Text(set.exercise)
                            Spacer()
                            Text(WorkoutFormat.set(set))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Удалить", systemImage: "trash", role: .destructive) {
                                store.workouts.removeSet(at: index)
                            }
                        }
                    }
                }
            }

            Section {
                Stepper(value: Binding(get: { store.workouts.restSeconds }, set: { store.workouts.restSeconds = $0 }), in: 0...600, step: 15) {
                    LabeledContent("Отдых", value: store.workouts.restSeconds == 0 ? String(localized: "без таймера") : WorkoutFormat.duration(store.workouts.restSeconds))
                }
            } footer: {
                Text("Таймер отдыха виден на экране блокировки, а по окончании придёт уведомление.")
            }
        }
        .keyboardDismissal(isFocused: focusedField != nil) { focusedField = nil }
        .navigationTitle(active.title ?? String(localized: "Тренировка"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Menu {
                    Button("Свернуть", systemImage: "chevron.down") { dismiss() }
                    Button("Отменить тренировку", systemImage: "xmark", role: .destructive) { confirmCancel = true }
                } label: {
                    Image(systemName: "chevron.down")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Завершить") { Task { await finish() } }
                    .disabled(isFinishing)
            }
        }
        .confirmationDialog("Отменить тренировку? Подходы не сохранятся.", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Отменить тренировку", role: .destructive) {
                store.workouts.cancel()
                dismiss()
            }
        }
        .onAppear {
            if let current = active.currentExercise, exercise.isEmpty {
                exercise = current
                prefill()
            }
        }
        .sensoryFeedback(.success, trigger: active.sets.count)
    }

    private var suggestions: [String] {
        let query = exercise.lowercased()
        let names = store.workouts.exerciseNames
        return query.isEmpty ? Array(names.prefix(8)) : names.filter { $0.lowercased().contains(query) }.prefix(8).map { $0 }
    }

    private var canAddSet: Bool {
        !exercise.trimmingCharacters(in: .whitespaces).isEmpty
            && (weight != nil || reps != nil || minutes != nil || kilometers != nil)
    }

    private func selectExercise() {
        focusedField = nil
        store.workouts.select(exercise: exercise)
        prefill()
    }

    /// Подставить вес и повторы из прошлого подхода этого упражнения.
    private func prefill() {
        guard let last = store.workouts.lastSet(of: exercise) else { return }
        weight = last.weightKg
        reps = last.reps
        minutes = last.durationSec.map { $0 / 60 }
        kilometers = last.distanceM.map { $0 / 1000 }
        showsMore = minutes != nil || kilometers != nil
    }

    private func addSet() {
        focusedField = nil
        let name = exercise.trimmingCharacters(in: .whitespacesAndNewlines)
        store.workouts.add(SetInput(
            exercise: name,
            weightKg: weight,
            reps: reps,
            durationSec: minutes.map { $0 * 60 },
            distanceM: kilometers.map { $0 * 1000 }
        ))
    }

    private func finish() async {
        focusedField = nil
        isFinishing = true
        defer { isFinishing = false }
        let hadSets = !(store.workouts.active?.sets.isEmpty ?? true)
        if await store.workouts.finish(), !hadSets {
            dismiss()
        }
    }
}

private enum WorkoutInputField: Hashable {
    case exercise, weight, reps, minutes, kilometers
}

private struct NumberField: View {
    let title: LocalizedStringKey
    @Binding var value: Double?
    var focus: FocusState<WorkoutInputField?>.Binding
    let field: WorkoutInputField

    init(_ title: LocalizedStringKey, value: Binding<Double?>, focus: FocusState<WorkoutInputField?>.Binding, field: WorkoutInputField) {
        self.title = title
        _value = value
        self.focus = focus
        self.field = field
    }

    var body: some View {
        TextField(title, value: $value, format: .number)
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .focused(focus, equals: field)
    }
}

private struct SuggestionStrip: View {
    let names: [String]
    let onPick: (String) -> Void

    var body: some View {
        if !names.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(names, id: \.self) { name in
                        Button(name) { onPick(name) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}

private struct RestTimer: View {
    let endsAt: Date
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Отдых")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(timerInterval: Date.now...endsAt, countsDown: true)
                .font(.title2.monospacedDigit().bold())
                .foregroundStyle(.tint)
            HStack(spacing: 6) {
                Button("+30 с") { store.workouts.extendRest(by: 30) }
                Button("Пропустить") { store.workouts.skipRest() }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
    }
}

private struct WorkoutResultView: View {
    let result: WorkoutResult
    let onDone: () -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: result.records.isEmpty ? "checkmark.seal.fill" : "trophy.fill")
                .font(.system(size: 72))
                .foregroundStyle(result.records.isEmpty ? AnyShapeStyle(.tint) : AnyShapeStyle(.yellow))
                .symbolEffect(.bounce, value: result.workout.id)
            Text("Тренировка сохранена")
                .font(.title2.bold())
            if result.xpGained > 0 {
                Text("+\(result.xpGained) XP")
                    .font(.title3.bold())
                    .foregroundStyle(.tint)
            }
            if !result.records.isEmpty {
                Text("Личный рекорд: \(result.records.joined(separator: ", "))")
                    .multilineTextAlignment(.center)
            }
            Text("Подходов: \(result.workout.sets.count)")
                .foregroundStyle(.secondary)
            // Плашка достижения на главном экране скрыта под этим окном — показываем здесь.
            if let achievement = store.progress.newAchievement {
                AchievementToast(achievement: achievement)
            }
            Spacer()
            Button("Готово") {
                store.progress.dismissAchievement()
                onDone()
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
        .sensoryFeedback(.success, trigger: result.workout.id)
    }
}

// MARK: - Детали

struct WorkoutDetailView: View {
    let workout: Workout
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    private var current: Workout {
        store.workouts.workouts.first { $0.id == workout.id } ?? workout
    }

    var body: some View {
        let workout = current
        List {
            Section {
                LabeledContent("Дата", value: DueFormat.label(date: workout.workoutDate, time: nil) ?? "")
                if let duration = workout.duration {
                    LabeledContent("Длительность", value: Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .wide)))
                }
                if let note = workout.note {
                    Text(note)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(workout.exercises, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.sets) { set in
                        HStack {
                            Text(WorkoutFormat.set(set))
                                .monospacedDigit()
                            Spacer()
                            if set.isPr {
                                Label("Рекорд", systemImage: "trophy.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
            }
            Section {
                Button("Удалить тренировку", role: .destructive) {
                    Task {
                        await store.workouts.delete(workout)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(workout.title ?? String(localized: "Тренировка"))
        .toolbar {
            Button("Изменить", systemImage: "pencil") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            WorkoutEditorView(workout: current)
        }
    }
}

private struct EditableWorkoutSet: Identifiable {
    let id = UUID()
    var input: SetInput
}

private struct WorkoutEditorView: View {
    let workout: Workout
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var title: String
    @State private var note: String
    @State private var sets: [EditableWorkoutSet]
    @State private var isSaving = false
    private enum Field: Hashable {
        case title, note, exercise(UUID), weight(UUID), reps(UUID), duration(UUID), distance(UUID)
    }
    @FocusState private var focusedField: Field?

    init(workout: Workout) {
        self.workout = workout
        _date = State(initialValue: workout.workoutDate.date())
        _title = State(initialValue: workout.title ?? "")
        _note = State(initialValue: workout.note ?? "")
        _sets = State(initialValue: workout.sets.map {
            EditableWorkoutSet(input: SetInput(
                exercise: $0.exercise, weightKg: $0.weightKg, reps: $0.reps,
                durationSec: $0.durationSec, distanceM: $0.distanceM
            ))
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $title)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.done)
                    DatePicker("Дата", selection: $date, displayedComponents: .date)
                    TextField("Заметка", text: $note, axis: .vertical)
                        .focused($focusedField, equals: .note)
                }
                ForEach($sets) { $set in
                    Section {
                        TextField("Упражнение", text: $set.input.exercise)
                            .focused($focusedField, equals: .exercise(set.id))
                            .submitLabel(.done)
                        LabeledContent("Вес, кг") {
                            TextField("—", value: $set.input.weightKg, format: .number)
                                .focused($focusedField, equals: .weight(set.id))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Повторы") {
                            TextField("—", value: $set.input.reps, format: .number)
                                .focused($focusedField, equals: .reps(set.id))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Время, с") {
                            TextField("—", value: $set.input.durationSec, format: .number)
                                .focused($focusedField, equals: .duration(set.id))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Дистанция, м") {
                            TextField("—", value: $set.input.distanceM, format: .number)
                                .focused($focusedField, equals: .distance(set.id))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        if !isValid(set.input) {
                            Text("Укажи упражнение и хотя бы один показатель в допустимых пределах.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Button("Удалить подход", systemImage: "trash", role: .destructive) {
                            sets.removeAll { $0.id == set.id }
                        }
                    }
                }
                Section {
                    Button("Добавить подход", systemImage: "plus") {
                        sets.append(EditableWorkoutSet(input: SetInput(exercise: "")))
                    }
                    .disabled(sets.count >= 300)
                }
            }
            .keyboardDismissal(isFocused: focusedField != nil) { focusedField = nil }
            .disabled(isSaving)
            .navigationTitle("Изменить тренировку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        focusedField = nil
                        Task { await save() }
                    }
                        .disabled(isSaving || sets.isEmpty || !sets.allSatisfy { isValid($0.input) } || title.count > 100 || note.count > 4000)
                }
            }
            .overlay(alignment: .bottom) {
                ErrorBanner(message: Binding(get: { store.workouts.errorMessage }, set: { store.workouts.errorMessage = $0 }))
            }
            .overlay {
                if isSaving { ProgressView() }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func isValid(_ set: SetInput) -> Bool {
        let name = set.exercise.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 100 && set.hasMeasure
            && (set.weightKg.map { $0.isFinite && (0...1000).contains($0) } ?? true)
            && (set.reps.map { (0...10000).contains($0) } ?? true)
            && (set.durationSec.map { (0...86400).contains($0) } ?? true)
            && (set.distanceM.map { $0.isFinite && (0...1_000_000).contains($0) } ?? true)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = WorkoutInput(
            workoutDate: LocalDate(date), title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            sets: sets.map { set in
                var input = set.input
                input.exercise = input.exercise.trimmingCharacters(in: .whitespacesAndNewlines)
                return input
            }
        )
        if await store.workouts.save(input, editing: workout) { dismiss() }
    }
}

struct ExerciseDetailView: View {
    let stats: ExerciseStats

    private enum Metric: Hashable {
        case weight, volume, reps, duration, distance
    }

    @State private var metric: Metric = .weight

    var body: some View {
        List {
            Section {
                if let best = stats.bestLabel {
                    LabeledContent("Рекорд", value: best)
                }
                LabeledContent("Занятий", value: "\(stats.sessions)")
                LabeledContent("Последнее", value: DueFormat.label(date: stats.lastDate, time: nil) ?? "")
            }
            if stats.history.count > 1 {
                Section {
                    Picker("Показатель", selection: $metric) {
                        ForEach(availableMetrics, id: \.self) { metric in
                            Text(title(metric)).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                    Chart(stats.history, id: \.date) { point in
                        if let value = value(point) {
                            LineMark(x: .value("Дата", point.date.date()), y: .value("Значение", value))
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Дата", point.date.date()), y: .value("Значение", value))
                        }
                    }
                    .frame(height: 200)
                } header: {
                    Text("Прогресс")
                }
            }
        }
        .navigationTitle(stats.name)
        .onAppear { metric = availableMetrics.first ?? .weight }
    }

    private var availableMetrics: [Metric] {
        var result: [Metric] = []
        if stats.bestWeightKg != nil { result += [.weight, .volume] }
        if stats.bestReps != nil, stats.bestWeightKg == nil { result.append(.reps) }
        if stats.bestDurationSec != nil { result.append(.duration) }
        if stats.bestDistanceM != nil { result.append(.distance) }
        return result
    }

    private func title(_ metric: Metric) -> LocalizedStringKey {
        switch metric {
        case .weight: "Вес"
        case .volume: "Объём"
        case .reps: "Повторы"
        case .duration: "Время"
        case .distance: "Дистанция"
        }
    }

    private func value(_ point: ExercisePoint) -> Double? {
        switch metric {
        case .weight: point.bestWeightKg
        case .volume: point.volumeKg
        case .reps: point.bestReps.map(Double.init)
        case .duration: point.bestDurationSec.map { Double($0) / 60 }
        case .distance: point.bestDistanceM.map { $0 / 1000 }
        }
    }
}
