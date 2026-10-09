import Foundation
import LevelUpKit
@preconcurrency import UserNotifications

/// Локальные напоминания по задачам. Сервер не нужен: iOS сама покажет уведомление в срок.
@MainActor
final class ReminderScheduler {
    private static let prefix = "task-"
    /// iOS хранит не больше 64 запланированных уведомлений на приложение.
    private static let limit = 60

    private var syncTask: Task<Void, Never>?

    func sync(_ tasks: [TaskItem]) {
        let now = Date.now
        // Сервер уже посчитал напоминания на неделю: с повторами и в обход занятого времени.
        let upcoming = tasks
            .filter { !$0.isDone }
            .flatMap { task in
                task.reminders.filter { $0 > now }.map { (id: task.id, title: task.title, at: $0) }
            }
            .sorted { $0.at < $1.at }
            .prefix(Self.limit)

        syncTask?.cancel()
        syncTask = Task {
            let center = UNUserNotificationCenter.current()
            let stale = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            guard !upcoming.isEmpty, !Task.isCancelled, await Self.authorize(center) else { return }

            for reminder in upcoming {
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = String(localized: "Напоминание из Level Up")
                content.sound = .default
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.at)
                let request = UNNotificationRequest(
                    identifier: "\(Self.prefix)\(reminder.id.uuidString)-\(Int(reminder.at.timeIntervalSince1970))",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
                try? await center.add(request)
            }
        }
    }

    func clear() {
        syncTask?.cancel()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private static func authorize(_ center: UNUserNotificationCenter) async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }
}

/// Показывать напоминания и тогда, когда приложение открыто.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
