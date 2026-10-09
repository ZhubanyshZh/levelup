import LevelUpKit
import SwiftUI
import WidgetKit

/// «Дневник»: серия дней подряд, а вечером — «Как прошёл день?», если сегодня ещё не писал.
struct JournalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JournalWidget", provider: SnapshotProvider(moment: .evening)) { entry in
            JournalWidgetView(entry: entry)
                .levelUpWidgetBackground()
        }
        .configurationDisplayName("Дневник")
        .description("Серия дней дневника и напоминание вечером.")
        .supportedFamilies([.systemSmall])
    }
}

struct JournalWidgetView: View {
    let entry: SnapshotEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var hasToday: Bool { snapshot.hasJournal(on: entry.day) }
    private var streak: Int { snapshot.journalStreak(on: entry.day) }
    private var isEvening: Bool { Calendar.current.component(.hour, from: entry.date) >= 18 }

    var body: some View {
        Group {
            if !snapshot.isSignedIn {
                WidgetUnavailableView(entry: entry)
            } else {
                content
            }
        }
        .widgetURL((hasToday ? AppRoute.journal : AppRoute.newJournalEntry).url)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "Дневник", systemImage: "book.fill")
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(streak, format: .number)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Image(systemName: "flame.fill")
                    .font(.title3)
                    .foregroundStyle(streak > 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                    .widgetAccentable()
            }
            Text("\(streak) дней подряд")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if hasToday {
                Label("Сегодня записано", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(Brand.accent)
                    .widgetAccentable()
            } else {
                Text(isEvening ? "Как прошёл день?" : "Запиши пару слов — +15 XP")
                    .font(.caption.bold())
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview(as: .systemSmall) {
    JournalWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}
