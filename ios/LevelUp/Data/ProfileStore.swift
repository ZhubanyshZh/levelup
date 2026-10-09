import Foundation
import LevelUpKit
import Observation

/// «Обо мне»: факты, которые ИИ учитывает при каждом разборе.
@MainActor
@Observable
final class ProfileStore {
    private(set) var facts: [ProfileFact]
    var errorMessage: String?

    private let api: APIClient
    private let cache = LocalCache<[ProfileFact]>(name: "facts")
    var onUnauthorized: () -> Void = {}
    /// Любое изменение данных — например, чтобы обновить виджеты.
    var onChange: () -> Void = {}

    init(api: APIClient) {
        self.api = api
        facts = cache.load() ?? []
    }

    func facts(in category: FactCategory) -> [ProfileFact] {
        facts.filter { $0.category == category }
    }

    func load() async {
        do {
            replaceAll(try await api.facts())
        } catch {
            report(error)
        }
    }

    func insert(_ created: [ProfileFact]) {
        guard !created.isEmpty else { return }
        replaceAll(facts.filter { fact in !created.contains { $0.id == fact.id } } + created)
    }

    func create(_ input: FactInput) async -> Bool {
        do {
            insert([try await api.createFact(input)])
            return true
        } catch {
            report(error)
            return false
        }
    }

    func update(_ fact: ProfileFact, with input: FactInput) async -> Bool {
        do {
            let saved = try await api.updateFact(id: fact.id, input)
            replaceAll(facts.map { $0.id == saved.id ? saved : $0 })
            return true
        } catch {
            report(error)
            return false
        }
    }

    func setActive(_ fact: ProfileFact, _ isActive: Bool) async {
        var input = FactInput(fact)
        input.isActive = isActive
        _ = await update(fact, with: input)
    }

    func delete(_ fact: ProfileFact) async {
        let previous = facts
        replaceAll(facts.filter { $0.id != fact.id })
        do {
            try await api.deleteFact(id: fact.id)
        } catch {
            replaceAll(previous)
            report(error)
        }
    }

    func reset() {
        facts = []
    }

    private func replaceAll(_ newFacts: [ProfileFact]) {
        facts = newFacts
        cache.save(newFacts)
        onChange()
    }

    private func report(_ error: Error) {
        if (error as? APIError)?.isUnauthorized == true {
            onUnauthorized()
        } else {
            errorMessage = ErrorText.message(for: error)
        }
    }
}
