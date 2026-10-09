import LevelUpKit
import SwiftUI
import WidgetKit

/// «Уровень»: кольцо опыта и сколько осталось до следующего уровня.
/// На экране блокировки — кольцо и строка над часами «Ур. 7 · задач: 3».
struct LevelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LevelWidget", provider: SnapshotProvider()) { entry in
            LevelWidgetView(entry: entry)
                .levelUpWidgetBackground()
        }
        .configurationDisplayName("Уровень")
        .description("Твой уровень и опыт.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline])
    }
}

struct LevelWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var fraction: Double { Double(snapshot.xp) / Double(max(snapshot.xpForNextLevel, 1)) }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            case .systemMedium: snapshot.isSignedIn ? AnyView(medium) : AnyView(WidgetUnavailableView(entry: entry))
            default: snapshot.isSignedIn ? AnyView(small) : AnyView(WidgetUnavailableView(entry: entry))
            }
        }
        .widgetURL(AppRoute.today.url)
    }

    private var circular: some View {
        Gauge(value: fraction) {
            Text("Ур")
        } currentValueLabel: {
            Text(snapshot.level, format: .number)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(Brand.accent)
    }

    private var inline: some View {
        let open = snapshot.tasks(on: entry.day).filter { $0.doneOn == nil }.count
        return Group {
            if !snapshot.isSignedIn {
                Text(verbatim: "Level Up")
            } else if open > 0 {
                Text("Ур. \(snapshot.level) · задач: \(open)")
            } else {
                Text("Ур. \(snapshot.level) · \(snapshot.xp)/\(snapshot.xpForNextLevel) XP")
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "Уровень", systemImage: "star.fill")
            Spacer(minLength: 0)
            Text("Ур. \(snapshot.level)")
                .font(.system(.title, design: .rounded).bold())
            ProgressView(value: fraction)
                .tint(Brand.accent)
                .widgetAccentable()
            Text("\(snapshot.xp) / \(snapshot.xpForNextLevel) XP")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            let today = snapshot.xpToday(on: entry.day)
            if today > 0 {
                Text("Сегодня +\(today) XP")
                    .font(.caption2.bold())
                    .foregroundStyle(Brand.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Brand.accent.opacity(0.15), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Brand.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
                VStack(spacing: -2) {
                    Text("Уровень")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(snapshot.level, format: .number)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                }
            }
            .frame(width: 108, height: 108)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(snapshot.xp) / \(snapshot.xpForNextLevel) XP")
                    .font(.headline.monospacedDigit())
                Text("До уровня \(snapshot.level + 1): \(snapshot.xpForNextLevel - snapshot.xp) XP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let today = snapshot.xpToday(on: entry.day)
                Label {
                    Text("Сегодня +\(today) XP")
                } icon: {
                    Image(systemName: "bolt.fill")
                }
                .font(.caption.bold())
                .foregroundStyle(today > 0 ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(.secondary))
                .widgetAccentable()
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview(as: .systemSmall) {
    LevelWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}

#Preview(as: .systemMedium) {
    LevelWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}
