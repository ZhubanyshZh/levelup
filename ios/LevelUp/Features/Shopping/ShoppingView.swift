import LevelUpKit
import SwiftUI

struct ShoppingView: View {
    @Environment(AppStore.self) private var store
    @State private var newItem = ""
    @FocusState private var isAdding: Bool

    var body: some View {
        @Bindable var shopping = store.shopping
        List {
            Section {
                HStack {
                    TextField("Добавить продукт", text: $newItem)
                        .focused($isAdding)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button(action: add) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel(Text("Добавить"))
                }
            }

            ForEach(shopping.lists, id: \.self) { listName in
                Section {
                    ForEach(shopping.toBuy.filter { $0.listName == listName }) { item in
                        row(item)
                    }
                } header: {
                    if let listName {
                        Text(verbatim: listName)
                    } else {
                        Text("Купить")
                    }
                }
            }

            if !shopping.bought.isEmpty {
                Section {
                    ForEach(shopping.bought) { item in
                        row(item)
                    }
                    Button("Убрать купленное", role: .destructive) {
                        Task { await shopping.clearBought() }
                    }
                } header: {
                    Text("Куплено")
                }
            }
        }
        .keyboardDismissal(isFocused: isAdding) { isAdding = false }
        .overlay {
            if shopping.items.isEmpty {
                ContentUnavailableView(
                    "Список пуст",
                    systemImage: "cart",
                    description: Text("Скажи «купить молоко и хлеб» в «Записать» или добавь вручную.")
                )
                .allowsHitTesting(false)
            }
        }
        .navigationTitle("Покупки")
        .refreshable { await shopping.load() }
        .overlay(alignment: .bottom) { ErrorBanner(message: $shopping.errorMessage) }
        .sensoryFeedback(.selection, trigger: shopping.bought.count)
    }

    private func row(_ item: ShoppingItem) -> some View {
        Button {
            Task { await store.shopping.toggle(item) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isBought ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isBought ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Text(item.name)
                    .strikethrough(item.isBought)
                    .foregroundStyle(item.isBought ? .secondary : .primary)
                Spacer()
                if let quantity = item.quantity {
                    Text(quantity)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button("Удалить", systemImage: "trash", role: .destructive) {
                Task { await store.shopping.delete(item) }
            }
        }
    }

    private func add() {
        isAdding = false
        let name = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newItem = ""
        Task { await store.shopping.add(name: name) }
    }
}
