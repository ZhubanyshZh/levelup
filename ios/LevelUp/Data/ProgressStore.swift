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
    var errorMessage: String?
    /// Последнее начисление для всплывающего «+N XP».
    private(set) var lastGain: Int?
    /// Только что полученное достижение — для праздничной плашки.
    private(set) var newAchievement: Achievement?

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
        newAchievement = nil
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
        let unlockedBefore = Set(old.achievements.filter(\.isUnlocked).map(\.code))
        // Каталог в старом кэше пуст — тогда это первая загрузка, а не новое достижение.
        if !old.achievements.isEmpty,
           let fresh = new.achievements.first(where: { $0.isUnlocked && !unlockedBefore.contains($0.code) }) {
            newAchievement = fresh
        }
    }

    func dismissAchievement() {
        newAchievement = nil
    }

    // MARK: Сферы

    func sphere(_ key: String?) -> Sphere? {
        key.flatMap { key in progress.spheres.first { $0.key == key } }
    }

    func createSphere(name: String, icon: String) async {
        await perform { _ = try await $0.createSphere(SphereInput(name: name, icon: icon)) }
    }

    func updateSphere(_ sphere: Sphere, name: String, icon: String) async {
        await perform { _ = try await $0.updateSphere(id: sphere.id, SphereInput(name: name, icon: icon)) }
    }

    func deleteSphere(_ sphere: Sphere) async {
        await perform { try await $0.deleteSphere(id: sphere.id) }
    }

    private func perform(_ operation: (APIClient) async throws -> Void) async {
        do {
            try await operation(api)
            await load()
        } catch let error as APIError where error.isUnauthorized {
            onUnauthorized()
        } catch {
            errorMessage = ErrorText.message(for: error)
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
