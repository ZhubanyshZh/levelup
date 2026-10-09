import Foundation
import LevelUpKit
import WidgetKit

/// Доступ виджетов к данным: снимок и очередь отметок в App Group, API с токенами
/// из общей с приложением группы Keychain.
struct WidgetEnvironment {
    let snapshots: SnapshotStore
    let pending: PendingActionStore
    let api: APIClient

    init(config: AppConfig = .fromBundle()) {
        snapshots = SnapshotStore(appGroupID: config.appGroupID)
        pending = PendingActionStore(appGroupID: config.appGroupID)
        // У интента виджета мало времени: не ждём сеть дольше нескольких секунд.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        api = APIClient(
            baseURL: config.apiBaseURL,
            tokenStore: KeychainTokenStore(accessGroup: config.appGroupID),
            session: URLSession(configuration: configuration)
        )
    }

    /// Отправляет отметки и подтягивает свежие задачи, покупки и опыт.
    /// Нет сети — отметки остаются в очереди, приложение отправит их при открытии.
    func sync() async {
        let outcome = await WidgetActionSender.flush(api: api, store: pending)
        guard outcome.sent > 0 else { return }
        async let progress = try? api.progress()
        async let tasks = try? api.tasks()
        async let shopping = try? api.shopping()
        let (freshProgress, freshTasks, freshShopping) = await (progress, tasks, shopping)

        let today = LocalDate.today()
        let waiting = pending.all()
        snapshots.update { snapshot in
            if let freshProgress { snapshot.apply(freshProgress, today: today) }
            if let freshTasks { snapshot.tasks = WidgetSnapshot.taskEntries(freshTasks, today: today) }
            if let freshShopping { snapshot.shopping = WidgetSnapshot.shoppingEntries(freshShopping) }
            snapshot.apply(waiting, today: today)
        }
    }
}

/// Одна точка во времени для виджета: снимок и день, на который он показывается.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var isAppGroupAvailable = true
    var relevance: TimelineEntryRelevance?

    var day: LocalDate { LocalDate(date) }
}

/// Общий источник для всех виджетов: читает снимок из App Group.
///
/// Перерисовка по расписанию: в полночь (новый день), утром и вечером (меняется,
/// какой виджет важнее в умном стеке) и после времени каждой задачи на сегодня.
struct SnapshotProvider: TimelineProvider {
    enum Moment {
        case anytime, morning, evening
    }

    /// Когда виджет особенно полезен — по этому iOS выбирает его в умном стеке.
    var moment: Moment = .anytime

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            let store = Self.store
            completion(entry(at: .now, snapshot: store.read(), isAvailable: store.isAvailable))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let store = Self.store
        let snapshot = store.read()
        let now = Date.now
        let calendar = Calendar.current
        let today = LocalDate(now, calendar: calendar)

        var dates: Set<Date> = [now]
        for task in snapshot?.tasks(on: today) ?? [] where task.dueDate == today {
            if let time = task.dueTime, let at = Self.date(on: today, time: time, calendar: calendar), at > now {
                dates.insert(at.addingTimeInterval(60))
            }
        }
        for hour in [6, 18] {
            if let at = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now), at > now {
                dates.insert(at)
            }
        }
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            dates.insert(midnight)
        }

        let entries = dates.sorted().map { entry(at: $0, snapshot: snapshot, isAvailable: store.isAvailable) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static var store: SnapshotStore {
        SnapshotStore(appGroupID: AppConfig.fromBundle().appGroupID)
    }

    private func entry(at date: Date, snapshot: WidgetSnapshot?, isAvailable: Bool) -> SnapshotEntry {
        let snapshot = snapshot ?? .signedOut
        return SnapshotEntry(
            date: date,
            snapshot: snapshot,
            isAppGroupAvailable: isAvailable,
            relevance: relevance(at: date, snapshot: snapshot)
        )
    }

    private func relevance(at date: Date, snapshot: WidgetSnapshot) -> TimelineEntryRelevance? {
        let hour = Calendar.current.component(.hour, from: date)
        switch moment {
        case .anytime:
            return nil
        case .morning:
            return TimelineEntryRelevance(score: (6..<12).contains(hour) ? 1 : 0.2)
        case .evening:
            let needsEntry = !snapshot.hasJournal(on: LocalDate(date))
            return TimelineEntryRelevance(score: (18..<24).contains(hour) && needsEntry ? 1 : 0.1)
        }
    }

    static func date(on day: LocalDate, time: String, calendar: Calendar) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day.date(calendar: calendar))
    }
}
