import LevelUpKit
import SwiftUI

struct TodayView: View {
    let onCapture: () -> Void

    @Environment(AppStore.self) private var store
    @State private var isTraining = false
    @State private var isAddingExpense = false
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

                Section {
                    NavigationLink {
                        CoachView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("ИИ-коуч", systemImage: "sparkles")
                                .font(.headline)
                            Text(store.coach.report(CoachKind.current())?.message ?? String(localized: "План дня, вечерний вопрос и обзор недели"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if store.workouts.active != nil {
                    Section {
                        Button {
                            isTraining = true
                        } label: {
                            Label("Идёт тренировка — продолжить", systemImage: "figure.strengthtraining.traditional")
                                .font(.headline)
                        }
                    }
                }

                let quests = store.progress.progress.quests
                if !quests.isEmpty {
                    Section {
                        ForEach(quests) { QuestRow(quest: $0) }
                    } header: {
                        Text("Квесты")
                    }
                }

                if let summary = store.finance.summary, store.finance.isCurrentMonth {
                    Section {
                        HStack {
                            NavigationLink {
                                FinanceView()
                            } label: {
                                LabeledContent {
                                    Text(Money.text(summary.spentToday, currency: summary.currency))
                                        .monospacedDigit()
                                } label: {
                                    Label("Потрачено сегодня", systemImage: "creditcard")
                                }
                            }
                            Button {
                                isAddingExpense = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("Новая трата"))
                        }
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
                    if tasks.today.isEmpty && tasks.todayFeed.isLoading {
                        ProgressView()
                    } else if tasks.today.isEmpty {
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
                    TaskPageFooter(feed: tasks.todayFeed)
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
            .sheet(isPresented: $isAddingExpense) {
                TransactionEditorView(row: nil)
            }
            .fullScreenCover(isPresented: $isTraining) {
                ActiveWorkoutView()
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
