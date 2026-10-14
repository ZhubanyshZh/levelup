import LevelUpKit
import SwiftUI

struct TaskFilterSheet: View {
    @Binding var filter: TaskFilter
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TaskFilter()

    init(filter: Binding<TaskFilter>) {
        _filter = filter
        _draft = State(initialValue: filter.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Срок", selection: $draft.due) {
                        ForEach(TaskFilter.Due.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Приоритет", selection: $draft.priority) {
                        Text("Любой").tag(TaskPriority?.none)
                        ForEach(TaskPriority.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                }
                Section {
                    Picker("Сфера", selection: $draft.sphere) {
                        Text("Все сферы").tag(String?.none)
                        ForEach(store.progress.progress.spheres) { sphere in
                            Text(sphere.name).tag(Optional(sphere.key))
                        }
                    }
                    Picker("Цель", selection: $draft.goalID) {
                        Text("Все цели").tag(UUID?.none)
                        ForEach(store.goals.goals) { goal in
                            Text(goal.title).tag(Optional(goal.id))
                        }
                    }
                } footer: {
                    Text("Фильтры работают вместе и применяются к списку и доске.")
                }
                Section {
                    Button("Сбросить фильтры") { draft = TaskFilter() }
                        .disabled(draft.activeCount == 0)
                }
            }
            .navigationTitle("Фильтры задач")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Применить") {
                        filter = draft
                        dismiss()
                    }
                }
            }
        }
    }
}

extension TaskFilter.Due {
    var title: LocalizedStringKey {
        switch self {
        case .any: "Любой срок"
        case .overdue: "Просрочено"
        case .today: "Сегодня"
        case .tomorrow: "Завтра"
        case .nextSevenDays: "Ближайшие 7 дней"
        case .noDate: "Без срока"
        }
    }
}

extension TaskFilter {
    @MainActor
    func summary(in store: AppStore) -> String {
        var labels: [String] = []
        switch due {
        case .any: break
        case .overdue: labels.append(String(localized: "Просрочено"))
        case .today: labels.append(String(localized: "Сегодня"))
        case .tomorrow: labels.append(String(localized: "Завтра"))
        case .nextSevenDays: labels.append(String(localized: "Ближайшие 7 дней"))
        case .noDate: labels.append(String(localized: "Без срока"))
        }
        if let priority {
            switch priority {
            case .low: labels.append(String(localized: "Низкий приоритет"))
            case .normal: labels.append(String(localized: "Обычный приоритет"))
            case .high: labels.append(String(localized: "Высокий приоритет"))
            }
        }
        if let sphere { labels.append(store.progress.sphere(sphere)?.name ?? sphere) }
        if let goalID { labels.append(store.goals.goal(goalID)?.title ?? String(localized: "Цель")) }
        return labels.joined(separator: " · ")
    }
}
