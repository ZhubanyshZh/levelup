import Foundation
import LevelUpKit

/// Копия данных на телефоне: приложение открывается мгновенно и показывает данные без сети.
struct LocalCache<Value: Codable> {
    let name: String

    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "LevelUp", directoryHint: .isDirectory)
    }

    private var url: URL { Self.directory.appending(path: "\(name).json") }

    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONCoding.makeDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try JSONCoding.makeEncoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Кэш — не источник истины: если не записался, данные просто загрузятся с сервера.
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    /// При выходе из аккаунта: данные одного пользователя не должны достаться другому.
    static func clearAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
