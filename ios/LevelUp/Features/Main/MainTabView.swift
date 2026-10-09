import LevelUpKit
import SwiftUI

enum MainTab: Hashable {
    case today, tasks, capture, journal, more
}

/// Что открыто поверх вкладок. Одно поле на всё: SwiftUI не покажет два листа сразу.
enum MainSheet: Identifiable, Hashable {
    case capture(AppRoute.CaptureMode)
    case journalEntry
    case shopping
    case finance
    case workout
    case goals
    case goal(UUID)
    case progress
    case coach(CoachKind)

    var id: Self { self }
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: MainTab = .today
    @State private var sheet: MainSheet?
    private let routes = RouteCenter.shared

    var body: some View {
        TabView(selection: $selection) {
            Tab("Сегодня", systemImage: "sun.max", value: .today) {
                TodayView { sheet = .capture(.voice) }
            }
            Tab("Задачи", systemImage: "checklist", value: .tasks) {
                TasksView()
            }
            // Не экран, а кнопка: открывает запись поверх текущей вкладки.
            Tab("Записать", systemImage: "mic.circle.fill", value: .capture) {
                Color.clear
            }
            Tab("Дневник", systemImage: "book", value: .journal) {
                JournalView()
            }
            Tab("Ещё", systemImage: "ellipsis.circle", value: .more) {
                MoreView()
            }
            .badge(store.captures.pendingCount)
        }
        .onChange(of: selection) { previous, current in
            if current == .capture {
                selection = previous
                sheet = .capture(.text)
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .capture(let mode):
                CaptureSheet(startMode: mode)
            case .journalEntry:
                JournalEditorView(entry: nil)
            case .shopping:
                closable { ShoppingView() }
            case .finance:
                closable { FinanceView() }
            case .workout:
                ActiveWorkoutView()
            case .goals:
                closable { GoalsView() }
            case .goal(let id):
                closable { GoalDetailView(goalID: id) }
            case .progress:
                closable { ProgressDetailView() }
            case .coach(let kind):
                closable { CoachView(kind: kind) }
            }
        }
        .overlay(alignment: .top) {
            if let gain = store.progress.lastGain {
                XPToast(gain: gain)
                    .padding(.top, 8)
            }
        }
        .animation(.spring(duration: 0.4), value: store.progress.lastGain)
        .overlay(alignment: .top) {
            // Пока открыт лист, плашку не видно — показываем, когда он закрыт.
            if let achievement = store.progress.newAchievement, sheet == nil, store.workouts.lastResult == nil {
                AchievementToast(achievement: achievement)
                    .padding(.top, 56)
                    .onTapGesture { store.progress.dismissAchievement() }
                    .task {
                        try? await Task.sleep(for: .seconds(3.5))
                        store.progress.dismissAchievement()
                    }
            }
        }
        .animation(.spring(duration: 0.4), value: store.progress.newAchievement)
        .sensoryFeedback(.success, trigger: store.progress.newAchievement)
        .overlay {
            if let level = store.progress.celebratedLevel {
                LevelUpCelebration(level: level) { store.progress.dismissCelebration() }
            }
        }
        .task { await store.refreshAll() }
        .onAppear(perform: openPendingRoute)
        .onChange(of: routes.pending) { openPendingRoute() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.refreshAll() }
            }
        }
    }

    /// Виджет, кнопка Пункта управления или Siri попросили открыть конкретное место.
    private func openPendingRoute() {
        guard let route = routes.take() else { return }
        switch route {
        case .capture(let mode):
            present(.capture(mode))
        case .newJournalEntry:
            selection = .journal
            present(.journalEntry)
        case .journal:
            sheet = nil
            selection = .journal
        case .shopping:
            present(.shopping)
        case .today:
            sheet = nil
            selection = .today
        case .finance:
            present(.finance)
        case .workout:
            if store.workouts.active == nil { store.workouts.start() }
            present(.workout)
        case .goals:
            present(.goals)
        case .goal(let id):
            present(.goal(id))
        case .progress:
            present(.progress)
        case .coach(let kind):
            present(.coach(kind))
        }
    }

    /// Раздел из «Ещё», открытый поверх вкладок, с кнопкой «Готово».
    private func closable(@ViewBuilder _ content: () -> some View) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Готово") { sheet = nil }
                    }
                }
        }
    }

    private func present(_ newSheet: MainSheet) {
        guard sheet != newSheet else { return }
        if sheet == nil {
            sheet = newSheet
            return
        }
        // Сначала закрыть открытый лист, потом показать новый.
        sheet = nil
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            sheet = newSheet
        }
    }
}
