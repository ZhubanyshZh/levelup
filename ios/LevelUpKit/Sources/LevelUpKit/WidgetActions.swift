import Foundation

/// Отметка, сделанная прямо в виджете: задача выполнена, покупка вычеркнута.
public enum WidgetAction: Codable, Sendable, Hashable {
    case task(id: UUID, done: Bool)
    case shopping(id: UUID, bought: Bool)

    /// Для одной записи хранится только последнее желаемое состояние.
    var key: String {
        switch self {
        case .task(let id, _): "task:\(id.uuidString)"
        case .shopping(let id, _): "shopping:\(id.uuidString)"
        }
    }
}

/// Очередь отметок из виджетов в App Group. Без сети отметки ждут здесь,
/// приложение отправляет их при следующем открытии.
public struct PendingActionStore: Sendable {
    private let file: AppGroupFile<[WidgetAction]>

    public init(appGroupID: String) {
        file = AppGroupFile(appGroupID: appGroupID, name: "widget-actions.json")
    }

    init(file: AppGroupFile<[WidgetAction]>) {
        self.file = file
    }

    public func all() -> [WidgetAction] {
        file.read() ?? []
    }

    public func add(_ action: WidgetAction) {
        file.update { actions in
            var list = (actions ?? []).filter { $0.key != action.key }
            list.append(action)
            actions = list
        }
    }

    /// Убирает отметку, только если её не поменяли, пока она отправлялась.
    public func remove(_ action: WidgetAction) {
        file.update { actions in
            let list = (actions ?? []).filter { $0 != action }
            actions = list.isEmpty ? nil : list
        }
    }

    public func clear() {
        file.delete()
    }
}

public enum WidgetActionSender {
    public struct Outcome: Sendable {
        /// Сколько отметок дошло до сервера.
        public var sent = 0
        /// Остались в очереди (нет сети).
        public var waiting = 0
    }

    /// Отправляет очередь по порядку. Нет сети — останавливается, остальное подождёт.
    /// Задача или покупка удалена на сервере — отметка просто убирается.
    @discardableResult
    public static func flush(api: APIClient, store: PendingActionStore) async -> Outcome {
        var outcome = Outcome()
        let actions = store.all()
        for (index, action) in actions.enumerated() {
            do {
                switch action {
                case .task(let id, let done):
                    _ = try await api.setTaskStatus(id: id, status: done ? .done : .todo)
                case .shopping(let id, let bought):
                    _ = try await api.setShoppingBought(id: id, isBought: bought)
                }
                store.remove(action)
                outcome.sent += 1
            } catch APIError.server(let status, _) where (400..<500).contains(status) {
                store.remove(action)
            } catch {
                outcome.waiting = actions.count - index
                break
            }
        }
        return outcome
    }
}
