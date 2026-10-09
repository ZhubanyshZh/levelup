import Foundation

/// JSON-файл в общем контейнере App Group. Его одновременно читают и пишут приложение,
/// виджеты и Siri, поэтому доступ идёт через NSFileCoordinator.
struct AppGroupFile<Value: Codable & Sendable>: Sendable {
    private let url: URL?

    init(appGroupID: String, name: String) {
        let container = appGroupID.isEmpty
            ? nil
            : FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        url = container?.appending(path: name)
    }

    /// Для тестов: файл в обычной папке.
    init(directory: URL, name: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: name)
    }

    var isAvailable: Bool { url != nil }

    func read() -> Value? {
        guard let url else { return nil }
        var value: Value?
        coordinate(url, writing: false) { value = decode($0) }
        return value
    }

    func write(_ value: Value) {
        guard let url else { return }
        coordinate(url, writing: true) { encode(value, to: $0) }
    }

    /// Прочитать, изменить и записать за один захват файла — чтобы два процесса не затёрли
    /// изменения друг друга.
    func update(_ change: (inout Value?) -> Void) {
        guard let url else { return }
        coordinate(url, writing: true) { url in
            var value = decode(url)
            change(&value)
            if let value {
                encode(value, to: url)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func delete() {
        guard let url else { return }
        coordinate(url, writing: true) { try? FileManager.default.removeItem(at: $0) }
    }

    private func coordinate(_ url: URL, writing: Bool, _ body: (URL) -> Void) {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        if writing {
            coordinator.coordinate(writingItemAt: url, options: [], error: &error, byAccessor: body)
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &error, byAccessor: body)
        }
    }

    private func decode(_ url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONCoding.makeDecoder().decode(Value.self, from: data)
    }

    private func encode(_ value: Value, to url: URL) {
        try? JSONCoding.makeEncoder().encode(value).write(to: url, options: .atomic)
    }
}
