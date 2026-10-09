import Foundation

public enum APIError: Error, Equatable, Sendable {
    /// Сессия недействительна — нужно войти заново.
    case unauthorized(code: String?)
    /// Сервер ответил ошибкой; `code` — машинный код из поля `detail`.
    case server(status: Int, code: String?)
    /// Нет сети или сервер недоступен. Сессию при этом не трогаем.
    case network(String)
    case decoding(String)

    public var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }
}
