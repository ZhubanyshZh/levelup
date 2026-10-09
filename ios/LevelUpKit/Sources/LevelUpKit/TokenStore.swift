import Foundation
import Synchronization

public protocol TokenStore: Sendable {
    func load() -> AuthTokens?
    func save(_ tokens: AuthTokens)
    func clear()
}

public struct KeychainTokenStore: TokenStore {
    private let item: KeychainItem

    /// accessGroup — App Group: тогда токены видят и виджеты (чтобы отмечать задачи без приложения).
    public init(service: String = "levelup.auth", accessGroup: String? = nil) {
        item = KeychainItem(service: service, account: "tokens", accessGroup: accessGroup)
    }

    public func load() -> AuthTokens? {
        item.read().flatMap { try? JSONDecoder().decode(AuthTokens.self, from: $0) }
    }

    public func save(_ tokens: AuthTokens) {
        if let data = try? JSONEncoder().encode(tokens) {
            item.write(data)
        }
    }

    public func clear() {
        item.delete()
    }
}

public final class InMemoryTokenStore: TokenStore {
    private let tokens: Mutex<AuthTokens?>

    public init(_ tokens: AuthTokens? = nil) {
        self.tokens = Mutex(tokens)
    }

    public func load() -> AuthTokens? { tokens.withLock { $0 } }
    public func save(_ newTokens: AuthTokens) { tokens.withLock { $0 = newTokens } }
    public func clear() { tokens.withLock { $0 = nil } }
}

/// Секрет для входа без регистрации. Создаётся один раз и живёт в Keychain,
/// поэтому переживает переустановку приложения.
public struct DeviceCredentialStore: Sendable {
    private let item = KeychainItem(service: "levelup.auth", account: "device-secret")

    public init() {}

    public func secret() -> String {
        if let data = item.read(), let existing = String(data: data, encoding: .utf8) {
            return existing
        }
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        let secret = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        item.write(Data(secret.utf8))
        return secret
    }
}
