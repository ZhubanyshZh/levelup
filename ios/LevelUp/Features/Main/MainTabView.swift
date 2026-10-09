import LevelUpKit
import SwiftUI

enum MainTab: Hashable {
    case today, tasks, capture, journal, more
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: MainTab = .today
    @State private var isCapturing = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("Сегодня", systemImage: "sun.max", value: .today) {
                TodayView { isCapturing = true }
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
                isCapturing = true
            }
        }
        .sheet(isPresented: $isCapturing) {
            CaptureSheet()
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.refreshAll() }
            }
        }
    }
}
