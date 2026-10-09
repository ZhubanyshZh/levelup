import AppIntents
import LevelUpKit
import SwiftUI
import WidgetKit

/// «Покупки»: что купить, с ✓ — вычеркнуть прямо в магазине, не открывая приложение.
struct ShoppingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ShoppingWidget", intent: SelectShoppingListIntent.self, provider: ShoppingProvider()) { entry in
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

    /// Выбранный в настройках список ("" — основной); без выбора — все.
    private var items: [WidgetSnapshot.ShoppingEntry] {
        guard let selection = entry.selection else { return entry.snapshot.shoppingToShow }
        return entry.snapshot.shoppingToShow.filter { ($0.listName ?? "") == selection }
    }

    private var title: LocalizedStringKey {
        guard let selection = entry.selection, !selection.isEmpty else { return "Покупки" }
        return LocalizedStringKey(stringLiteral: selection)
    }
    private var toBuy: Int { items.filter { !$0.isBought }.count }

    var body: some View {
        Group {
            if !entry.snapshot.isSignedIn {
                WidgetUnavailableView(entry: entry)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    WidgetHeader(title: title, systemImage: "cart.fill") {
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

// MARK: - Выбор списка

struct ShoppingListEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Список покупок"
    static let defaultQuery = ShoppingListQuery()

    /// "" — основной список.
    var id: String

    var displayRepresentation: DisplayRepresentation {
        id.isEmpty ? DisplayRepresentation(title: "Основной") : DisplayRepresentation(title: "\(id)")
    }
}

struct ShoppingListQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ShoppingListEntity] {
        identifiers.map(ShoppingListEntity.init)
    }

    func suggestedEntities() async throws -> [ShoppingListEntity] {
        let names = (SnapshotProvider.store.read()?.shopping ?? []).map { $0.listName ?? "" }
        var unique = [""]
        for name in names where !unique.contains(name) { unique.append(name) }
        return unique.map(ShoppingListEntity.init)
    }
}

struct SelectShoppingListIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Список покупок"
    static let description = IntentDescription("Какой список показывать. Без выбора — все.")

    @Parameter(title: "Список")
    var list: ShoppingListEntity?
}

struct ShoppingProvider: AppIntentTimelineProvider {
    private let base = SnapshotProvider()

    func placeholder(in context: Context) -> SnapshotEntry {
        base.placeholder(in: context)
    }

    func snapshot(for configuration: SelectShoppingListIntent, in context: Context) async -> SnapshotEntry {
        var entry = context.isPreview ? base.placeholder(in: context) : base.current()
        entry.selection = configuration.list?.id
        return entry
    }

    func timeline(for configuration: SelectShoppingListIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        let entries = base.entries().map { entry in
            var entry = entry
            entry.selection = configuration.list?.id
            return entry
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}
