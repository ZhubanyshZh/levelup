import LevelUpKit
import SwiftUI
import WidgetKit

/// «Быстрый ввод»: одно касание — и приложение уже слушает. Средний — четыре входа сразу.
struct QuickCaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickCaptureWidget", provider: SnapshotProvider()) { entry in
            QuickCaptureWidgetView(entry: entry)
                .levelUpWidgetBackground()
        }
        .configurationDisplayName("Быстрый ввод")
        .description("Запись голосом в одно касание.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

struct QuickCaptureWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(Brand.accent.gradient, in: .circle)
                .widgetAccentable()
            VStack(spacing: 2) {
                Text("Записать")
                    .font(.headline)
                Text("ИИ разложит сам")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(AppRoute.capture(.voice).url)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: "Быстрый ввод", systemImage: "bolt.fill")
            HStack(spacing: 10) {
                tile("Голос", systemImage: "mic.fill", route: .capture(.voice), prominent: true)
                tile("Текст", systemImage: "keyboard", route: .capture(.text))
                tile("Дневник", systemImage: "book.fill", route: .newJournalEntry)
                tile("Покупки", systemImage: "cart.fill", route: .shopping)
            }
        }
    }

    private func tile(_ title: LocalizedStringKey, systemImage: String, route: AppRoute, prominent: Bool = false) -> some View {
        Link(destination: route.url) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(Brand.accent))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        prominent ? AnyShapeStyle(Brand.accent.gradient) : AnyShapeStyle(Brand.accent.opacity(0.14)),
                        in: .rect(cornerRadius: 14)
                    )
                    .widgetAccentable()
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "mic.fill")
                .font(.title2.weight(.semibold))
                .widgetAccentable()
        }
        .widgetURL(AppRoute.capture(.voice).url)
        .accessibilityLabel(Text("Записать"))
    }
}

#Preview(as: .systemSmall) {
    QuickCaptureWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}

#Preview(as: .systemMedium) {
    QuickCaptureWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}
