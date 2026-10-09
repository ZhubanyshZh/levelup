import Foundation
import LevelUpKit
import Observation

/// Уровень и опыт. После действий, приносящих опыт, показывает «+N XP» и праздник нового уровня.
@MainActor
@Observable
final class ProgressStore {
    private(set) var progress: LevelProgress
    /// Новый уровень, который нужно отпраздновать (показывается поверх всего).
    private(set) var celebratedLevel: Int?
    /// Последнее начисление для всплывающего «+N XP».
    private(set) var lastGain: Int?

    private let api: APIClient
    private let cache = LocalCache<LevelProgress>(name: "progress")
    private var gainToken = 0
    var onUnauthorized: () -> Void = {}
    /// Каждое обновление — в виджеты.
    var onChange: (LevelProgress) -> Void = { _ in }

    init(api: APIClient) {
        self.api = api
        progress = cache.load() ?? .initial
    }

    func load() async {
        await fetch(announce: false)
    }

    /// После выполнения задачи, записи в дневник и т. п.
    func refreshAfterAction() async {
        await fetch(announce: true)
    }

    func dismissCelebration() {
        celebratedLevel = nil
    }

    func reset() {
        progress = .initial
        celebratedLevel = nil
        lastGain = nil
    }

    private func fetch(announce: Bool) async {
        do {
            apply(try await api.progress(), announce: announce)
        } catch let error as APIError where error.isUnauthorized {
            onUnauthorized()
        } catch {
            // Уровень — не критичен: покажем последний известный.
        }
    }

    private func apply(_ new: LevelProgress, announce: Bool) {
        let old = progress
        progress = new
        cache.save(new)
        onChange(new)
        guard announce else { return }
        let gain = new.totalXp - old.totalXp
        if gain > 0 {
            showGain(gain)
        }
        if new.level > old.level {
            celebratedLevel = new.level
        }
    }

    private func showGain(_ gain: Int) {
        lastGain = gain
        gainToken += 1
        let token = gainToken
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if token == gainToken {
                lastGain = nil
            }
        }
    }
}
