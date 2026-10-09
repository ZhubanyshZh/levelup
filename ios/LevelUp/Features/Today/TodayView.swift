import LevelUpKit
import SwiftUI

struct TodayView: View {
    let onCapture: () -> Void

    @Environment(AppStore.self) private var store
    @Environment(SessionStore.self) private var session
    @State private var editing: TaskItem?
    @State private var isWritingJournal = false

    var body: some View {
        @Bindable var tasks = store.tasks
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ProgressDetailView()
                    } label: {
                        LevelCard(progress: store.progress.progress)
                    }
                }

                if store.captures.pendingCount > 0 {
                    Section {
                        NavigationLink {
                            InboxView()
                        } label: {
                            Label("Во «Входящих»: \(store.captures.pendingCount)", systemImage: "tray.full")
                        }
                    }
                }

                if !store.journal.hasEntryToday || !store.shopping.toBuy.isEmpty {
                    Section {
                        if !store.journal.hasEntryToday {
                            Button {
                                isWritingJournal = true
                            } label: {
                                Label("Как проходит день? Запиши пару слов — +15 XP", systemImage: "book")
                            }
                        }
                        if !store.shopping.toBuy.isEmpty {
                            NavigationLink {
                                ShoppingView()
                            } label: {
                                Label("Купить: \(store.shopping.toBuy.count)", systemImage: "cart")
                            }
                        }
                    }
                }

                Section("Сегодня") {
                    if tasks.today.isEmpty {
                        Button(action: onCapture) {
                            Label("На сегодня ничего. Нажми, чтобы записать дела голосом.", systemImage: "mic")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(tasks.today) { task in
                            TaskRow(task: task) {
                                Task { await tasks.toggleDone(task) }
                            }
                            .onTapGesture { editing = task }
                        }
                    }
                }
            }
            .navigationTitle(greeting)
            .refreshable { await store.refreshAll() }
            .sheet(item: $editing) { task in
                TaskEditorView(task: task)
            }
            .sheet(isPresented: $isWritingJournal) {
                JournalEditorView(entry: nil)
            }
            .overlay(alignment: .bottom) {
                ErrorBanner(message: $tasks.errorMessage)
            }
        }
    }

    private var greeting: String {
        guard case .signedIn(let user) = session.state,
              let name = user.displayName?.split(separator: " ").first
        else { return String(localized: "Привет!") }
        return String(localized: "Привет, \(String(name))!")
    }
}
