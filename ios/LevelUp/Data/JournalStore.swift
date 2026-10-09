import Foundation
import LevelUpKit
import Observation

@MainActor
@Observable
final class JournalStore {
    struct DayGroup: Identifiable {
        let date: LocalDate
        let entries: [JournalEntry]
        var id: LocalDate { date }
    }

    private(set) var entries: [JournalEntry]
    var errorMessage: String?

    private let api: APIClient
    private let cache = LocalCache<[JournalEntry]>(name: "journal")
    var onUnauthorized: () -> Void = {}
    /// Любое изменение данных — например, чтобы обновить виджеты.
    var onChange: () -> Void = {}
    /// Запись в дневнике может принести опыт.
    var onProgressChange: () -> Void = {}

    init(api: APIClient) {
        self.api = api
        entries = cache.load() ?? []
    }

    var hasEntryToday: Bool {
        let today = LocalDate.today()
        return entries.contains { $0.entryDate == today }
    }

    var groupedByDay: [DayGroup] {
        Dictionary(grouping: entries, by: \.entryDate)
            .map { DayGroup(date: $0.key, entries: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.date > $1.date }
    }

    /// Среднее настроение по дням — для полоски настроения.
    func moodByDay(last days: Int) -> [(date: LocalDate, mood: Int?)] {
        let today = LocalDate.today()
        return (0..<days).reversed().map { offset in
            let date = today.adding(days: -offset)
            let moods = entries.filter { $0.entryDate == date }.compactMap(\.mood)
            let average = moods.isEmpty ? nil : Int((Double(moods.reduce(0, +)) / Double(moods.count)).rounded())
            return (date, average)
        }
    }

    func load() async {
        do {
            replaceAll(try await api.journal())
        } catch {
            report(error)
        }
    }

    func insert(_ created: [JournalEntry]) {
        guard !created.isEmpty else { return }
        replaceAll(created + entries.filter { entry in !created.contains { $0.id == entry.id } })
    }

    func create(_ input: JournalInput) async -> Bool {
        do {
            insert([try await api.createJournal(input)])
            onProgressChange()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func update(_ entry: JournalEntry, with input: JournalInput) async -> Bool {
        do {
            let saved = try await api.updateJournal(id: entry.id, input)
            replaceAll(entries.map { $0.id == saved.id ? saved : $0 })
            if saved.entryDate != entry.entryDate {
                // Опыт за день дневника переезжает вместе с записью.
                onProgressChange()
            }
            return true
        } catch {
            report(error)
            return false
        }
    }

    func delete(_ entry: JournalEntry) async {
        let previous = entries
        replaceAll(entries.filter { $0.id != entry.id })
        do {
            try await api.deleteJournal(id: entry.id)
            onProgressChange()
        } catch {
            replaceAll(previous)
            report(error)
        }
    }

    func reset() {
        entries = []
    }

    private func replaceAll(_ newEntries: [JournalEntry]) {
        entries = newEntries
        cache.save(newEntries)
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
