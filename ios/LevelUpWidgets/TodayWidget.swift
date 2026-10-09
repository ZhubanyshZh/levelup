import LevelUpKit
import SwiftUI
import WidgetKit

/// «Сегодня»: задачи дня с ✓ (+XP). Большой — лента дня с занятым временем из «Обо мне».
/// На экране блокировки — ближайшая задача со временем.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: SnapshotProvider(moment: .morning)) { entry in
            TodayWidgetView(entry: entry)
                .levelUpWidgetBackground()
        }
        .configurationDisplayName("Сегодня")
        .description("Задачи на сегодня — отмечай прямо здесь.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct TodayWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var tasks: [WidgetSnapshot.TaskEntry] { snapshot.tasks(on: entry.day) }
    private var openCount: Int { tasks.filter { $0.doneOn == nil }.count }

    var body: some View {
        Group {
            if !snapshot.isSignedIn {
                if family == .accessoryRectangular {
                    Text("Войди в приложение")
                } else {
                    WidgetUnavailableView(entry: entry)
                }
            } else {
                switch family {
                case .accessoryRectangular: rectangular
                case .systemLarge: large
                default: medium
                }
            }
        }
        .widgetURL(AppRoute.today.url)
    }

    private var header: some View {
        WidgetHeader(title: "Сегодня", systemImage: "sun.max.fill") {
            let xp = snapshot.xpToday(on: entry.day)
            if xp > 0 {
                Text("+\(xp) XP")
            } else if openCount > 0 {
                Text("Задач: \(openCount)")
            }
        }
    }

    // MARK: Средний

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if tasks.isEmpty {
                emptyState
            } else {
                let limit = tasks.count > 4 ? 3 : 4
                ForEach(tasks.prefix(limit)) { task in
                    WidgetTaskRow(task: task, day: entry.day)
                }
                if tasks.count > limit {
                    Text("Ещё \(tasks.count - limit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Большой — лента дня

    private enum DayItem: Identifiable {
        case busy(WidgetSnapshot.BusySlot)
        case task(WidgetSnapshot.TaskEntry)

        var id: String {
            switch self {
            case .busy(let slot): "busy-\(slot.start)-\(slot.title)"
            case .task(let task): task.id.uuidString
            }
        }
    }

    /// Просроченное сверху, потом по времени (вместе с занятым временем), потом без времени.
    private var dayItems: [DayItem] {
        let overdue = tasks.filter { ($0.dueDate ?? entry.day) < entry.day }.map(DayItem.task)
        let timed: [(String, DayItem)] =
            snapshot.busySlots(on: entry.day).map { ($0.start, .busy($0)) }
            + tasks.filter { $0.dueDate == entry.day && $0.dueTime != nil }.map { ($0.dueTime ?? "", .task($0)) }
        let untimed = tasks.filter { ($0.dueDate == entry.day && $0.dueTime == nil) || $0.dueDate == nil }.map(DayItem.task)
        return overdue + timed.sorted { $0.0 < $1.0 }.map(\.1) + untimed
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            if tasks.isEmpty && snapshot.busySlots(on: entry.day).isEmpty {
                emptyState
            } else {
                let items = dayItems
                let limit = items.count > 11 ? 10 : 11
                ForEach(items.prefix(limit)) { item in
                    switch item {
                    case .busy(let slot): BusyRow(slot: slot)
                    case .task(let task): WidgetTaskRow(task: task, day: entry.day)
                    }
                }
                if items.count > limit {
                    Text("Ещё \(items.count - limit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            Text("На сегодня задач нет")
                .font(.subheadline.weight(.medium))
            Link(destination: AppRoute.capture(.voice).url) {
                Label("Записать дела голосом", systemImage: "mic.fill")
                    .font(.caption.bold())
                    .foregroundStyle(Brand.accent)
                    .widgetAccentable()
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Экран блокировки

    @ViewBuilder
    private var rectangular: some View {
        if let next = snapshot.nextTimedTask(after: entry.date) {
            VStack(alignment: .leading, spacing: 1) {
                Label(next.dueTime ?? "", systemImage: "clock")
                    .font(.headline)
                    .widgetAccentable()
                Text(next.title)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text("Сегодня")
                    .font(.headline)
                    .widgetAccentable()
                if openCount == 0 {
                    Text("Задач нет")
                } else {
                    Text("Задач: \(openCount)")
                    if let first = tasks.first(where: { $0.doneOn == nil }) {
                        Text(first.title)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Занятое время в ленте дня: «12:30–14:00 Жума».
private struct BusyRow: View {
    let slot: WidgetSnapshot.BusySlot

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.footnote)
                .frame(width: 20)
            Text(verbatim: "\(slot.start)–\(slot.end)")
                .font(.caption.monospacedDigit())
            Text(slot.title)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(.fill.tertiary, in: .rect(cornerRadius: 6))
    }
}

#Preview(as: .systemMedium) {
    TodayWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}

#Preview(as: .systemLarge) {
    TodayWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}
