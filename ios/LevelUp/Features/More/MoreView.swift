import LevelUpKit
import SwiftUI

struct MoreView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("speechLocale") private var speechLocale = SpeechLocale.default

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        GoalsView()
                    } label: {
                        LabeledContent {
                            if !store.goals.active.isEmpty {
                                Text(store.goals.active.count, format: .number)
                            }
                        } label: {
                            Label("Цели", systemImage: "flag")
                        }
                    }
                    NavigationLink {
                        FinanceView()
                    } label: {
                        LabeledContent {
                            if let summary = store.finance.summary, store.finance.isCurrentMonth, summary.spent > 0 {
                                Text(Money.short(summary.spent, currency: summary.currency))
                            }
                        } label: {
                            Label("Финансы", systemImage: "creditcard")
                        }
                    }
                    NavigationLink {
                        WorkoutsView()
                    } label: {
                        LabeledContent {
                            if store.workouts.active != nil {
                                Text("идёт")
                                    .foregroundStyle(.tint)
                            } else if !store.workouts.thisWeek.isEmpty {
                                Text(store.workouts.thisWeek.count, format: .number)
                            }
                        } label: {
                            Label("Тренировки", systemImage: "figure.strengthtraining.traditional")
                        }
                    }
                    NavigationLink {
                        ProgressDetailView()
                    } label: {
                        LabeledContent {
                            Text("Ур. \(store.progress.progress.level)")
                        } label: {
                            Label("Прогресс", systemImage: "star")
                        }
                    }
                }

                Section {
                    NavigationLink {
                        ShoppingView()
                    } label: {
                        LabeledContent {
                            if !store.shopping.toBuy.isEmpty {
                                Text(store.shopping.toBuy.count, format: .number)
                            }
                        } label: {
                            Label("Покупки", systemImage: "cart")
                        }
                    }
                    NavigationLink {
                        AboutMeView()
                    } label: {
                        LabeledContent {
                            Text(store.profile.facts.count, format: .number)
                        } label: {
                            Label("Обо мне", systemImage: "person.text.rectangle")
                        }
                    }
                    NavigationLink {
                        InboxView()
                    } label: {
                        LabeledContent {
                            if store.captures.pendingCount > 0 {
                                Text(store.captures.pendingCount, format: .number)
                            }
                        } label: {
                            Label("Входящие", systemImage: "tray")
                        }
                    }
                }

                Section("ИИ и голос") {
                    NavigationLink {
                        CoachView()
                    } label: {
                        Label("ИИ-коуч", systemImage: "sparkles.rectangle.stack")
                    }
                    NavigationLink {
                        AISettingsView()
                    } label: {
                        LabeledContent {
                            if let provider = store.ai.settings?.activeProvider {
                                Text(verbatim: provider.title)
                            } else {
                                Text("Не настроен")
                                    .foregroundStyle(.orange)
                            }
                        } label: {
                            Label("ИИ-помощник", systemImage: "sparkles")
                        }
                    }
                    Picker(selection: $speechLocale) {
                        Text(verbatim: "Русский").tag("ru-RU")
                        Text(verbatim: "English").tag("en-US")
                    } label: {
                        Label("Голосовой ввод", systemImage: "waveform")
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    NavigationLink {
                        AccountView()
                    } label: {
                        Label("Аккаунт", systemImage: "person.crop.circle")
                    }
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Проверка связи", systemImage: "stethoscope")
                    }
                }
            }
            .navigationTitle("Ещё")
        }
    }
}
