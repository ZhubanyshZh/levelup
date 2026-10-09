import LevelUpKit
import SwiftUI
import WidgetKit

/// «Покупки»: что купить, с ✓ — вычеркнуть прямо в магазине, не открывая приложение.
struct ShoppingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShoppingWidget", provider: SnapshotProvider()) { entry in
            ShoppingWidgetView(entry: entry)
                .levelUpWidgetBackground()
        }
        .configurationDisplayName("Покупки")
        .description("Список покупок — вычёркивай купленное прямо здесь.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ShoppingWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var items: [WidgetSnapshot.ShoppingEntry] { entry.snapshot.shoppingToShow }
    private var toBuy: Int { items.filter { !$0.isBought }.count }

    var body: some View {
        Group {
            if !entry.snapshot.isSignedIn {
                WidgetUnavailableView(entry: entry)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    WidgetHeader(title: "Покупки", systemImage: "cart.fill") {
                        if toBuy > 0 {
                            Text(toBuy, format: .number)
                        }
                    }
                    if items.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .widgetURL(AppRoute.shopping.url)
    }

    private var capacity: Int { family == .systemLarge ? 20 : 6 }

    private var list: some View {
        let shown = Array(items.prefix(items.count > capacity ? capacity - 1 : capacity))
        return VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                ForEach(Array(stride(from: 0, to: shown.count, by: 2)), id: \.self) { index in
                    GridRow {
                        WidgetShoppingRow(item: shown[index], showsQuantity: family == .systemLarge)
                        if index + 1 < shown.count {
                            WidgetShoppingRow(item: shown[index + 1], showsQuantity: family == .systemLarge)
                        } else {
                            Color.clear.frame(height: 1)
                        }
                    }
                }
            }
            if items.count > shown.count {
                Text("Ещё \(items.count - shown.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            Text("Список пуст")
                .font(.subheadline.weight(.medium))
            Link(destination: AppRoute.capture(.voice).url) {
                Label("Скажи «купить молоко и хлеб»", systemImage: "mic.fill")
                    .font(.caption.bold())
                    .foregroundStyle(Brand.accent)
                    .widgetAccentable()
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview(as: .systemMedium) {
    ShoppingWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}
