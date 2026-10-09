import AppIntents
import Foundation
import LevelUpKit
import WidgetKit

/// ✓ на задаче прямо в виджете. Отметка видна сразу, на сервер уходит следом
/// (за выполнение начисляется опыт). Без сети — ждёт в очереди.
struct ToggleTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Отметить задачу"
    static let isDiscoverable = false

    @Parameter(title: "Задача")
    var taskID: String

    init() {}

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        let environment = WidgetEnvironment()
        let today = LocalDate.today()
        var action: WidgetAction?
        environment.snapshots.update { snapshot in
            guard let index = snapshot.tasks.firstIndex(where: { $0.id == id }) else { return }
            let done = snapshot.tasks[index].doneOn == nil
            snapshot.tasks[index].doneOn = done ? today : nil
            action = .task(id: id, done: done)
        }
        guard let action else { return .result() }
        environment.pending.add(action)
        WidgetCenter.shared.reloadAllTimelines()
        await environment.sync()
        return .result()
    }
}

/// ✓ на покупке в виджете — вычеркнуть купленное.
struct ToggleShoppingIntent: AppIntent {
    static let title: LocalizedStringResource = "Вычеркнуть покупку"
    static let isDiscoverable = false

    @Parameter(title: "Покупка")
    var itemID: String

    init() {}

    init(itemID: UUID) {
        self.itemID = itemID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: itemID) else { return .result() }
        let environment = WidgetEnvironment()
        var action: WidgetAction?
        environment.snapshots.update { snapshot in
            guard let index = snapshot.shopping.firstIndex(where: { $0.id == id }) else { return }
            snapshot.shopping[index].isBought.toggle()
            action = .shopping(id: id, bought: snapshot.shopping[index].isBought)
        }
        guard let action else { return .result() }
        environment.pending.add(action)
        WidgetCenter.shared.reloadAllTimelines()
        await environment.sync()
        return .result()
    }
}
