import Foundation

public struct User: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var displayName: String?
    public var email: String?
    public var avatarUrl: String?
    public var locale: String
    public var timezone: String
    public var currency: String?
    public var authProviders: [String]
    public let createdAt: Date

    public var isGuest: Bool { !authProviders.contains { $0 != "device" } }
}

public struct AuthTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var accessExpiresAt: Date
    public var refreshToken: String
    public var refreshExpiresAt: Date

    public init(accessToken: String, accessExpiresAt: Date, refreshToken: String, refreshExpiresAt: Date) {
        self.accessToken = accessToken
        self.accessExpiresAt = accessExpiresAt
        self.refreshToken = refreshToken
        self.refreshExpiresAt = refreshExpiresAt
    }
}

public struct AuthResponse: Decodable, Sendable {
    public let accessToken: String
    public let accessExpiresAt: Date
    public let refreshToken: String
    public let refreshExpiresAt: Date
    public let user: User
    public let isNewUser: Bool

    public var tokens: AuthTokens {
        AuthTokens(
            accessToken: accessToken,
            accessExpiresAt: accessExpiresAt,
            refreshToken: refreshToken,
            refreshExpiresAt: refreshExpiresAt
        )
    }
}

public struct HealthStatus: Decodable, Sendable, Equatable {
    public let status: String
    public let database: String
    public let version: String
}

/// Что приложение сообщает о себе при входе (язык и часовой пояс нового аккаунта).
public struct ClientInfo: Encodable, Sendable {
    public var locale: String?
    public var timezone: String?
    public var deviceName: String?

    public init(locale: String?, timezone: String?, deviceName: String?) {
        self.locale = locale
        self.timezone = timezone
        self.deviceName = deviceName
    }
}

public struct UserUpdate: Encodable, Sendable {
    public var displayName: String?
    public var locale: String?
    public var timezone: String?
    public var currency: String?

    public init(displayName: String? = nil, locale: String? = nil, timezone: String? = nil, currency: String? = nil) {
        self.displayName = displayName
        self.locale = locale
        self.timezone = timezone
        self.currency = currency
    }
}
