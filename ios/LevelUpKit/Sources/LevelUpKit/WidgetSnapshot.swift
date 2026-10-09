import Foundation

/// Компактные данные для виджетов. Приложение пишет их в общее хранилище App Group
/// после каждого изменения, виджеты только читают.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public var isSignedIn: Bool
    public var displayName: String?
    public var level: Int
    public var xp: Int
    public var xpForNextLevel: Int
    public var updatedAt: Date

    public init(isSignedIn: Bool, displayName: String?, level: Int, xp: Int, xpForNextLevel: Int, updatedAt: Date) {
        self.isSignedIn = isSignedIn
        self.displayName = displayName
        self.level = level
        self.xp = xp
        self.xpForNextLevel = xpForNextLevel
        self.updatedAt = updatedAt
    }

    public static let signedOut = WidgetSnapshot(
        isSignedIn: false, displayName: nil, level: 1, xp: 0, xpForNextLevel: 100, updatedAt: .distantPast
    )
}

public enum SnapshotStoreError: Error {
    case appGroupUnavailable
}

public struct SnapshotStore: Sendable {
    public let appGroupID: String

    public init(appGroupID: String) {
        self.appGroupID = appGroupID
    }

    /// false — App Group не настроена или недоступна при этой подписи.
    public var isAvailable: Bool { fileURL != nil }

    public func read() -> WidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONCoding.makeDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func write(_ snapshot: WidgetSnapshot) throws {
        guard let fileURL else { throw SnapshotStoreError.appGroupUnavailable }
        try JSONCoding.makeEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }

    private var fileURL: URL? {
        guard !appGroupID.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return nil }
        return container.appending(path: "widget-snapshot.json")
    }
}
