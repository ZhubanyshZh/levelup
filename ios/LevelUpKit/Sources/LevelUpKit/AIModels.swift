import Foundation

public enum AIProviderKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case gemini, openai

    public var id: String { rawValue }
}

public struct AIProviderInfo: Codable, Sendable, Hashable {
    public var provider: AIProviderKind
    public var hasKey: Bool
    public var keyHint: String?
    public var model: String
    public var defaultModel: String
}

public struct AISettings: Codable, Sendable, Hashable {
    public var activeProvider: AIProviderKind?
    public var providers: [AIProviderInfo]

    public func info(for provider: AIProviderKind) -> AIProviderInfo? {
        providers.first { $0.provider == provider }
    }
}

public struct AITestResult: Decodable, Sendable, Hashable {
    public var ok: Bool
    public var errorCode: String?
    /// false — ключ рабочий, но выбранной модели у провайдера нет.
    public var modelAvailable: Bool?
}

struct AICredentialInput: Encodable {
    var apiKey: String?
    var model: String?
}
