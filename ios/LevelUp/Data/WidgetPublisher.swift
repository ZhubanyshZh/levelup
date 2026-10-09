import Foundation
import LevelUpKit
import WidgetKit

/// Снимок для виджетов в App Group. Приложение пересобирает его после каждого изменения
/// и перерисовывает виджеты, только если содержимое правда поменялось.
@MainActor
final class WidgetPublisher {
    let pending: PendingActionStore
    private let snapshots: SnapshotStore
    private var scheduled: Task<Void, Never>?
    /// После выхода опоздавшие загрузки не должны вернуть в виджеты данные прошлого аккаунта.
    private var isSignedIn = false

    init(appGroupID: String) {
        snapshots = SnapshotStore(appGroupID: appGroupID)
        pending = PendingActionStore(appGroupID: appGroupID)
    }

    /// Изменения часто идут пачкой (загрузка всех разделов) — пишем один раз в конце.
    func schedule(_ make: @escaping @MainActor () -> WidgetSnapshot) {
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled, self.isSignedIn else { return }
            self.publish(make())
        }
    }

    func publish(_ snapshot: WidgetSnapshot) {
        var snapshot = snapshot
        // Отметки из виджетов, которые ещё не дошли до сервера, не должны пропасть с экрана.
        snapshot.apply(pending.all())
        if let current = snapshots.read(), current.hasSameContent(as: snapshot) {
            return
        }
        try? snapshots.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Вход выполнен: с этого момента снимки публикуются.
    func start() {
        isSignedIn = true
    }

    func signOut() {
        isSignedIn = false
        scheduled?.cancel()
        pending.clear()
        publish(.signedOut)
    }
}
