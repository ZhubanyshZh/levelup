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
                NavigationStack {
                    ShoppingView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Готово") { self.sheet = nil }
                            }
                        }
                }
            }
        }
        .overlay(alignment: .top) {
            if let gain = store.progress.lastGain {
                XPToast(gain: gain)
                    .padding(.top, 8)
            }
        }
        .animation(.spring(duration: 0.4), value: store.progress.lastGain)
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
