import Foundation
import LevelUpKit
import Observation

@MainActor
@Observable
final class AISettingsStore {
    private(set) var settings: AISettings?
    private(set) var models: [AIProviderKind: [String]] = [:]
    private(set) var testResults: [AIProviderKind: AITestResult] = [:]
    private(set) var busyProvider: AIProviderKind?
    var errorMessage: String?

    private let api: APIClient
    var onUnauthorized: () -> Void = {}

    init(api: APIClient) {
        self.api = api
    }

    var isConfigured: Bool { settings?.activeProvider != nil }

    func load() async {
        await perform { self.settings = try await self.api.aiSettings() }
    }

    func saveKey(_ key: String, for provider: AIProviderKind) async -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let ok = await perform(provider) {
            self.settings = try await self.api.saveAIProvider(provider, apiKey: trimmed, model: nil)
        }
        if ok {
            await test(provider)
            await loadModels(provider)
        }
        return ok
    }

    func setModel(_ model: String, for provider: AIProviderKind) async {
        await perform(provider) {
            self.settings = try await self.api.saveAIProvider(provider, apiKey: nil, model: model)
        }
        testResults[provider] = nil
    }

    func setActive(_ provider: AIProviderKind) async {
        await perform { self.settings = try await self.api.setActiveAIProvider(provider) }
    }

    func deleteKey(for provider: AIProviderKind) async {
        await perform(provider) { self.settings = try await self.api.deleteAIProvider(provider) }
        models[provider] = nil
        testResults[provider] = nil
    }

    func test(_ provider: AIProviderKind) async {
        await perform(provider) { self.testResults[provider] = try await self.api.testAIProvider(provider) }
    }

    func loadModels(_ provider: AIProviderKind) async {
        guard settings?.info(for: provider)?.hasKey == true else { return }
        do {
            models[provider] = try await api.aiModels(provider)
        } catch {
            // Список моделей — подсказка; без него остаётся текущая модель.
        }
    }

    func reset() {
        settings = nil
        models = [:]
        testResults = [:]
    }

    @discardableResult
    private func perform(_ provider: AIProviderKind? = nil, _ operation: () async throws -> Void) async -> Bool {
        busyProvider = provider
        errorMessage = nil
        defer { busyProvider = nil }
        do {
            try await operation()
            return true
        } catch let error as APIError where error.isUnauthorized {
            onUnauthorized()
        } catch {
            errorMessage = ErrorText.message(for: error)
        }
        return false
    }
}
