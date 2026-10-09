import Foundation
import LevelUpKit
@preconcurrency import UserNotifications

@MainActor
final class CoachReminderScheduler {
    private var syncTask: Task<Void, Never>?
    private static let prefix = "coach-"

    func authorize() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        return [.authorized, .provisional, .ephemeral].contains(status)
    }

    func sync(enabled: Bool, facts: [ProfileFact]) {
        syncTask?.cancel()
        syncTask = Task {
            let center = UNUserNotificationCenter.current()
            let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            guard !Task.isCancelled else { return }
            center.removePendingNotificationRequests(withIdentifiers: old)
            guard enabled else { return }
            let status = await center.notificationSettings().authorizationStatus
            guard [.authorized, .provisional, .ephemeral].contains(status), !Task.isCancelled else { return }
            let schedules = facts.filter { $0.isActive && $0.category == .schedule }.compactMap(\.schedule)
            for event in CoachReminderPlan.events(schedules: schedules) {
                guard !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = event.kind.title
                content.body = String(localized: "Открой коуча — выберем следующий шаг.")
                content.sound = .default
                content.userInfo = ["route": AppRoute.coach(event.kind).url.absoluteString]
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: event.date)
                let identifier = "\(Self.prefix)\(event.kind.rawValue)-\(Int(event.date.timeIntervalSince1970))"
                try? await center.add(UNNotificationRequest(identifier: identifier, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
                if Task.isCancelled { center.removePendingNotificationRequests(withIdentifiers: [identifier]); return }
            }
        }
    }

    func clear() {
        syncTask?.cancel()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
