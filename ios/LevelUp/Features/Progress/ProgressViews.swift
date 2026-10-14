import LevelUpKit
import SwiftUI

/// Уровень подробно: кольцо, сферы, квесты, достижения и за что начислен опыт.
struct ProgressDetailView: View {
    @Environment(AppStore.self) private var store
    @State private var isEditingSpheres = false

    var body: some View {
        let progress = store.progress.progress
        List {
            Section {
                VStack(spacing: 12) {
                    LevelRing(progress: progress)
                        .frame(width: 160, height: 160)
                    Text("Всего \(progress.totalXp) XP")
                        .font(.headline)
                    Text("До уровня \(progress.level + 1): \(progress.xpForNextLevel - progress.xpInLevel) XP")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if progress.streakDays > 0 {
                        Label("Серия: \(progress.streakDays) дн.", systemImage: "flame.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } footer: {
                if progress.streakDays > 0 {
                    Text("Серия — дни подряд с опытом. Один пропущенный день её не обнулит.")
                        .frame(maxWidth: .infinity)
                }
            }

            if !progress.quests.isEmpty {
                Section("Квесты") {
                    ForEach(progress.quests) { QuestRow(quest: $0) }
                }
            }

            if !progress.spheres.isEmpty {
                Section {
                    ForEach(progress.spheres) { SphereRow(sphere: $0) }
                } header: {
                    HStack {
                        Text("Сферы жизни")
                        Spacer()
                        Button("Изменить") { isEditingSpheres = true }
                            .font(.caption)
                    }
                }
            }

            if !progress.achievements.isEmpty {
                Section("Достижения") {
                    AchievementGrid(achievements: progress.achievements)
                        .padding(.vertical, 6)
                }
            }

            Section("Как получить опыт") {
                Label("Задача: 5–30 XP — чем сложнее, тем больше", systemImage: "checkmark.circle")
                Label("Запись в дневнике: 15 XP в день", systemImage: "book")
                Label("Тренировка: 25 XP, личный рекорд: +50", systemImage: "figure.strengthtraining.traditional")
                Label("Неделя в рамках бюджета: 50 XP", systemImage: "banknote")
                Label("Шаг к цели: 100 XP, цель достигнута: 500", systemImage: "flag")
                Label("Квест: 50–150 XP", systemImage: "map")
                Label("Мелкие задачи приносят опыт до 10 раз в день", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }

            if !progress.recent.isEmpty {
                Section("Недавно") {
                    ForEach(Array(progress.recent.enumerated()), id: \.offset) { _, event in
                        HStack {
                            Image(systemName: XPSource.symbol(event.sourceType))
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(XPSource.title(event))
                                    .lineLimit(2)
                                HStack(spacing: 6) {
                                    if let sphere = store.progress.sphere(event.sphere) {
                                        Text(verbatim: sphere.icon)
                                    }
                                    Text(event.createdAt, format: .relative(presentation: .named))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("+\(event.amount)")
                                .font(.subheadline.monospacedDigit().bold())
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .navigationTitle("Прогресс")
        .refreshable { await store.progress.load() }
        .task { await store.progress.load() }
        .sheet(isPresented: $isEditingSpheres) { SpheresEditorView() }
    }
}

/// Значок и подпись начисления опыта.
enum XPSource {
    static func symbol(_ source: String) -> String {
        switch source {
        case "journal": "book"
        case "workout": "figure.strengthtraining.traditional"
        case "pr": "trophy"
        case "budget": "banknote"
        case "goal_step", "goal": "flag"
        case "quest": "map"
        default: "checkmark.circle"
        }
    }

    static func title(_ event: XPEvent) -> String {
        switch event.sourceType {
        case "budget": String(localized: "Неделя в рамках бюджета: \(event.title)")
        case "pr": String(localized: "Рекорд: \(event.title)")
        case "goal": String(localized: "Цель достигнута: \(event.title)")
        case "quest": String(localized: "Квест выполнен")
        default: event.title
        }
    }
}

struct QuestRow: View {
    let quest: Quest

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: quest.isDone ? "checkmark.seal.fill" : quest.symbol)
                .font(.title3)
                .foregroundStyle(quest.isDone ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(quest.title)
                        .strikethrough(quest.isDone)
                    Spacer()
                    Text("+\(quest.reward) XP")
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                }
                ProgressView(value: quest.fraction)
                    .tint(quest.isDone ? .green : .accentColor)
                HStack {
                    Text("\(quest.progress) из \(quest.target)")
                    Spacer()
                    Text(quest.period == .day ? String(localized: "сегодня") : String(localized: "до \(quest.periodEnd.date().formatted(.dateTime.day().month()))"))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SphereRow: View {
    let sphere: Sphere

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: sphere.icon)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(sphere.name)
                    Spacer()
                    Text("Ур. \(sphere.level)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.tint)
                }
                ProgressView(value: sphere.fraction)
                Text("\(sphere.xpInLevel) / \(sphere.xpForNextLevel) XP")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AchievementGrid: View {
    let achievements: [Achievement]
    @State private var selected: Achievement?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 14) {
            ForEach(achievements) { achievement in
                Button {
                    selected = achievement
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: AchievementCatalog.symbol(achievement.code))
                            .font(.title2)
                            .foregroundStyle(achievement.isUnlocked ? AnyShapeStyle(.yellow.gradient) : AnyShapeStyle(.quaternary))
                            .frame(width: 52, height: 52)
                            .background(achievement.isUnlocked ? AnyShapeStyle(Color.yellow.opacity(0.15)) : AnyShapeStyle(.fill.quaternary), in: .circle)
                        Text(AchievementCatalog.title(achievement.code))
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .foregroundStyle(achievement.isUnlocked ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .alert(selected.map { AchievementCatalog.title($0.code) } ?? "", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            Button("OK") { selected = nil }
        } message: {
            if let selected {
                if let date = selected.achievedAt {
                    Text("\(AchievementCatalog.detail(selected.code))\n\(date.formatted(date: .long, time: .omitted))")
                } else {
                    Text(AchievementCatalog.detail(selected.code))
                }
            }
        }
    }
}

/// Сферы: переименовать стандартные, добавить и удалить свои.
struct SpheresEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var newIcon = "⭐"
    @State private var renaming: Sphere?
    @State private var renameText = ""
    private enum Field: Hashable { case icon, name }
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.progress.progress.spheres) { sphere in
                        HStack {
                            Text(verbatim: "\(sphere.icon) \(sphere.name)")
                            Spacer()
                            Button("Переименовать") {
                                renameText = sphere.name
                                renaming = sphere
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                        .swipeActions {
                            if sphere.isCustom {
                                Button("Удалить", systemImage: "trash", role: .destructive) {
                                    Task { await store.progress.deleteSphere(sphere) }
                                }
                            }
                        }
                    }
                } footer: {
                    Text("ИИ сам относит задачи и цели к сферам. Стандартные сферы можно переименовать, свои — удалить.")
                }
                Section("Своя сфера") {
                    HStack {
                        TextField("⭐", text: $newIcon)
                            .frame(width: 44)
                            .focused($focusedField, equals: .icon)
                            .submitLabel(.done)
                        TextField("Название", text: $newName)
                            .focused($focusedField, equals: .name)
                            .submitLabel(.done)
                            .onSubmit(addSphere)
                        Button("Добавить", action: addSphere)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .keyboardDismissal(isFocused: focusedField != nil) { focusedField = nil }
            .navigationTitle("Сферы жизни")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Готово") { dismiss() }
            }
            .alert("Название сферы", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Название", text: $renameText)
                Button("Сохранить") {
                    guard let sphere = renaming else { return }
                    let name = renameText
                    Task { await store.progress.updateSphere(sphere, name: name, icon: sphere.icon) }
                    renaming = nil
                }
                Button("Отмена", role: .cancel) { renaming = nil }
            }
        }
    }

    private func addSphere() {
        focusedField = nil
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let icon = newIcon
        newName = ""
        Task { await store.progress.createSphere(name: name, icon: icon) }
    }
}

struct LevelRing: View {
    let progress: LevelProgress

    var body: some View {
        ZStack {
            Circle()
                .stroke(.fill.tertiary, lineWidth: 14)
            Circle()
                .trim(from: 0, to: Double(progress.xpInLevel) / Double(max(progress.xpForNextLevel, 1)))
                .stroke(.tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress.xpInLevel)
            VStack(spacing: 0) {
                Text("Уровень")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(progress.level, format: .number)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }
        }
    }
}

/// «+15 XP» сверху экрана после действий, приносящих опыт.
struct XPToast: View {
    let gain: Int

    var body: some View {
        Label("+\(gain) XP", systemImage: "star.fill")
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.tint, in: .capsule)
            .shadow(radius: 8, y: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Праздник нового уровня поверх всего приложения.
struct LevelUpCelebration: View {
    let level: Int
    let onDismiss: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(spacing: 16) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.yellow, .tint)
                    .symbolEffect(.bounce, value: appeared)
                Text("Новый уровень!")
                    .font(.title2.bold())
                Text("Уровень \(level)")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(.tint)
                Text("Так держать — каждый шаг считается.")
                    .foregroundStyle(.secondary)
                Button("Отлично", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(32)
            .background(.regularMaterial, in: .rect(cornerRadius: 28))
            .padding(32)
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)
        }
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.4)) { appeared = true }
        }
    }
}

/// Плашка «Новое достижение» сверху экрана.
struct AchievementToast: View {
    let achievement: Achievement

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: AchievementCatalog.symbol(achievement.code))
                .font(.title3)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 1) {
                Text("Новое достижение")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(AchievementCatalog.title(achievement.code))
                    .font(.subheadline.bold())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .capsule)
        .shadow(radius: 8, y: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
