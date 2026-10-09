import LevelUpKit
import SwiftUI
import WidgetKit

/// Виджет уровня. На этапе 0 он заодно проверяет, что App Group работает:
/// данные сюда приходят только через общее хранилище.
struct LevelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LevelWidget", provider: LevelProvider()) { entry in
            LevelWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Уровень")
        .description("Твой уровень и опыт.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct LevelEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let isAppGroupAvailable: Bool
}

struct LevelProvider: TimelineProvider {
    private let store = SnapshotStore(appGroupID: AppConfig.fromBundle().appGroupID)

    func placeholder(in context: Context) -> LevelEntry {
        LevelEntry(date: .now, snapshot: .preview, isAppGroupAvailable: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (LevelEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LevelEntry>) -> Void) {
        // Приложение само перезагружает виджет после изменений.
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> LevelEntry {
        LevelEntry(date: .now, snapshot: store.read(), isAppGroupAvailable: store.isAvailable)
    }
}

struct LevelWidgetView: View {
    let entry: LevelEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        default:
            small
        }
    }

    private var snapshot: WidgetSnapshot { entry.snapshot ?? .signedOut }

    private var circular: some View {
        Gauge(value: Double(snapshot.xp), in: 0...Double(max(snapshot.xpForNextLevel, 1))) {
            Text("Ур")
        } currentValueLabel: {
            Text(snapshot.level, format: .number)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(Brand.accent)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(verbatim: "Level Up")
            } icon: {
                Image(systemName: "chevron.up.2")
            }
            .font(.caption.bold())
            .foregroundStyle(Brand.accent)

            Spacer(minLength: 0)

            if !entry.isAppGroupAvailable {
                Text("Нет доступа к данным приложения")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !snapshot.isSignedIn {
                Text("Войди в приложение")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Ур. \(snapshot.level)")
                    .font(.title.bold())
                ProgressView(value: Double(snapshot.xp), total: Double(max(snapshot.xpForNextLevel, 1)))
                    .tint(Brand.accent)
                Text("\(snapshot.xp) / \(snapshot.xpForNextLevel) XP")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

extension WidgetSnapshot {
    static let preview = WidgetSnapshot(
        isSignedIn: true, displayName: nil, level: 7, xp: 640, xpForNextLevel: 1000, updatedAt: .now
    )
}
