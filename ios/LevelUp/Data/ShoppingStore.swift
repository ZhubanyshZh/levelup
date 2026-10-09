import Foundation
import LevelUpKit
import Observation

@MainActor
@Observable
final class ShoppingStore {
    private(set) var items: [ShoppingItem]
    var errorMessage: String?

    private let api: APIClient
    private let cache = LocalCache<[ShoppingItem]>(name: "shopping")
    var onUnauthorized: () -> Void = {}

    init(api: APIClient) {
        self.api = api
        items = cache.load() ?? []
    }

    var toBuy: [ShoppingItem] {
        items.filter { !$0.isBought }.sorted { $0.position < $1.position }
    }

    var bought: [ShoppingItem] {
        items.filter(\.isBought).sorted { ($0.boughtAt ?? .distantPast) > ($1.boughtAt ?? .distantPast) }
    }

    /// Списки, в которых есть что купить. nil — основной список, он всегда первый.
    var lists: [String?] {
        var names: [String?] = []
        for item in toBuy where !names.contains(item.listName) {
            names.append(item.listName)
        }
        return names.sorted { ($0 ?? "") < ($1 ?? "") }
    }

    func load() async {
        do {
            replaceAll(try await api.shopping())
        } catch {
            report(error)
        }
    }

    func insert(_ created: [ShoppingItem]) {
        guard !created.isEmpty else { return }
        replaceAll(items.filter { item in !created.contains { $0.id == item.id } } + created)
    }

    func add(name: String, listName: String? = nil) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            insert([try await api.createShopping(ShoppingInput(name: trimmed, listName: listName))])
        } catch {
            report(error)
        }
    }

    func toggle(_ item: ShoppingItem) async {
        var updated = item
        updated.isBought.toggle()
        updated.boughtAt = updated.isBought ? .now : nil
        let previous = items
        replaceAll(items.map { $0.id == item.id ? updated : $0 })
        do {
            let saved = try await api.updateShopping(id: item.id, ShoppingUpdate(updated))
            replaceAll(items.map { $0.id == saved.id ? saved : $0 })
        } catch {
            replaceAll(previous)
            report(error)
        }
    }

    func delete(_ item: ShoppingItem) async {
        let previous = items
        replaceAll(items.filter { $0.id != item.id })
        do {
            try await api.deleteShopping(id: item.id)
        } catch {
            replaceAll(previous)
            report(error)
        }
    }

    func clearBought() async {
        let previous = items
        replaceAll(items.filter { !$0.isBought })
        do {
            try await api.clearBoughtShopping()
        } catch {
            replaceAll(previous)
            report(error)
        }
    }

    func reset() {
        items = []
    }

    private func replaceAll(_ newItems: [ShoppingItem]) {
        items = newItems
        cache.save(newItems)
    }

    private func report(_ error: Error) {
        if (error as? APIError)?.isUnauthorized == true {
            onUnauthorized()
        } else {
            errorMessage = ErrorText.message(for: error)
        }
    }
}
