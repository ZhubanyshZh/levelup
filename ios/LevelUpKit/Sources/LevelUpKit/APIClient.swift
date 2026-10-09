import Foundation

/// Клиент API Level Up.
///
/// Сам обновляет access token (заранее и по ответу 401), параллельные запросы делят
/// одно обновление. Сессия сбрасывается только если сервер отверг refresh-токен —
/// при проблемах с сетью токены остаются, чтобы пользователя не разлогинивало.
public actor APIClient {
    public nonisolated let baseURL: URL
    private let tokenStore: any TokenStore
    private let session: URLSession
    private let decoder = JSONCoding.makeDecoder()
    private let encoder = JSONCoding.makeEncoder()
    private var refreshTask: Task<AuthTokens, Error>?

    /// За сколько секунд до истечения access token обновляем его заранее.
    private let refreshMargin: TimeInterval = 60

    public init(baseURL: URL, tokenStore: any TokenStore, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.session = session
    }

    public nonisolated var hasSession: Bool { tokenStore.load() != nil }

    // MARK: - Эндпоинты

    public func health() async throws -> HealthStatus {
        try await send(Request(method: "GET", path: "health"))
    }

    public func signInWithGoogle(idToken: String, client: ClientInfo) async throws -> AuthResponse {
        try await signIn(path: "auth/google", body: SignInBody(idToken: idToken, client: client))
    }

    public func signInWithDevice(secret: String, client: ClientInfo) async throws -> AuthResponse {
        try await signIn(path: "auth/device", body: SignInBody(deviceSecret: secret, client: client))
    }

    public func me() async throws -> User {
        try await sendAuthorized(Request(method: "GET", path: "me"))
    }

    public func updateMe(_ update: UserUpdate) async throws -> User {
        try await sendAuthorized(Request(method: "PATCH", path: "me", body: encoder.encode(update)))
    }

    public func linkGoogle(idToken: String) async throws -> User {
        try await sendAuthorized(Request(method: "POST", path: "auth/link/google", body: encoder.encode(["id_token": idToken])))
    }

    // MARK: Задачи

    public func tasks() async throws -> [TaskItem] {
        try await sendAuthorized(Request(method: "GET", path: "tasks"))
    }

    public func createTask(_ draft: TaskDraft) async throws -> TaskItem {
        try await sendAuthorized(Request(method: "POST", path: "tasks", body: encoder.encode(draft)))
    }

    public func updateTask(id: UUID, _ update: TaskUpdate) async throws -> TaskItem {
        try await sendAuthorized(Request(method: "PATCH", path: "tasks/\(id.uuidString)", body: encoder.encode(update)))
    }

    /// Только статус — для отметки из виджета, где нет остальных полей задачи.
    public func setTaskStatus(id: UUID, status: TaskStatus) async throws -> TaskItem {
        try await sendAuthorized(Request(method: "PATCH", path: "tasks/\(id.uuidString)", body: encoder.encode(["status": status])))
    }

    public func deleteTask(id: UUID) async throws {
        try await sendAuthorizedEmpty(Request(method: "DELETE", path: "tasks/\(id.uuidString)"))
    }

    // MARK: «Обо мне»

    public func facts() async throws -> [ProfileFact] {
        try await sendAuthorized(Request(method: "GET", path: "profile/facts"))
    }

    public func createFact(_ input: FactInput) async throws -> ProfileFact {
        try await sendAuthorized(Request(method: "POST", path: "profile/facts", body: encoder.encode(input)))
    }

    public func updateFact(id: UUID, _ input: FactInput) async throws -> ProfileFact {
        try await sendAuthorized(Request(method: "PATCH", path: "profile/facts/\(id.uuidString)", body: encoder.encode(input)))
    }

    public func deleteFact(id: UUID) async throws {
        try await sendAuthorizedEmpty(Request(method: "DELETE", path: "profile/facts/\(id.uuidString)"))
    }

    // MARK: Ввод и «Входящие»

    /// Разбор ИИ может занять десятки секунд, поэтому таймаут больше обычного.
    public func capture(_ request: CaptureRequest) async throws -> CaptureResult {
        try await sendAuthorized(Request(method: "POST", path: "captures", body: encoder.encode(request), timeout: 75))
    }

    public func inbox() async throws -> [Capture] {
        try await sendAuthorized(Request(method: "GET", path: "captures"))
    }

    public func confirmCapture(id: UUID, items: [CaptureItem]) async throws -> CaptureResult {
        try await sendAuthorized(Request(method: "POST", path: "captures/\(id.uuidString)/confirm", body: encoder.encode(["items": items])))
    }

    public func retryCapture(id: UUID) async throws -> CaptureResult {
        try await sendAuthorized(Request(method: "POST", path: "captures/\(id.uuidString)/retry", timeout: 75))
    }

    public func undoCapture(id: UUID) async throws -> Capture {
        try await sendAuthorized(Request(method: "POST", path: "captures/\(id.uuidString)/undo"))
    }

    public func dismissCapture(id: UUID) async throws {
        try await sendAuthorizedEmpty(Request(method: "DELETE", path: "captures/\(id.uuidString)"))
    }

    // MARK: Дневник

    public func journal() async throws -> [JournalEntry] {
        try await sendAuthorized(Request(method: "GET", path: "journal"))
    }

    public func createJournal(_ input: JournalInput) async throws -> JournalEntry {
        try await sendAuthorized(Request(method: "POST", path: "journal", body: encoder.encode(input)))
    }

    public func updateJournal(id: UUID, _ input: JournalInput) async throws -> JournalEntry {
        try await sendAuthorized(Request(method: "PATCH", path: "journal/\(id.uuidString)", body: encoder.encode(input)))
    }

    public func deleteJournal(id: UUID) async throws {
        try await sendAuthorizedEmpty(Request(method: "DELETE", path: "journal/\(id.uuidString)"))
    }

    // MARK: Покупки

    public func shopping() async throws -> [ShoppingItem] {
        try await sendAuthorized(Request(method: "GET", path: "shopping"))
    }

    public func createShopping(_ input: ShoppingInput) async throws -> ShoppingItem {
        try await sendAuthorized(Request(method: "POST", path: "shopping", body: encoder.encode(input)))
    }

    public func updateShopping(id: UUID, _ update: ShoppingUpdate) async throws -> ShoppingItem {
        try await sendAuthorized(Request(method: "PATCH", path: "shopping/\(id.uuidString)", body: encoder.encode(update)))
    }

    /// Только «куплено» — для отметки из виджета.
    public func setShoppingBought(id: UUID, isBought: Bool) async throws -> ShoppingItem {
        try await sendAuthorized(Request(method: "PATCH", path: "shopping/\(id.uuidString)", body: encoder.encode(["is_bought": isBought])))
    }

    public func deleteShopping(id: UUID) async throws {
        try await sendAuthorizedEmpty(Request(method: "DELETE", path: "shopping/\(id.uuidString)"))
    }

    public func clearBoughtShopping() async throws {
        try await sendAuthorizedEmpty(Request(method: "POST", path: "shopping/clear-bought"))
    }

    // MARK: Прогресс

    public func progress() async throws -> LevelProgress {
        try await sendAuthorized(Request(method: "GET", path: "progress"))
    }

    // MARK: Настройки ИИ

    public func aiSettings() async throws -> AISettings {
        try await sendAuthorized(Request(method: "GET", path: "me/ai"))
    }

    public func saveAIProvider(_ provider: AIProviderKind, apiKey: String?, model: String?) async throws -> AISettings {
        let body = try encoder.encode(AICredentialInput(apiKey: apiKey, model: model))
        return try await sendAuthorized(Request(method: "PUT", path: "me/ai/\(provider.rawValue)", body: body))
    }

    public func deleteAIProvider(_ provider: AIProviderKind) async throws -> AISettings {
        try await sendAuthorized(Request(method: "DELETE", path: "me/ai/\(provider.rawValue)"))
    }

    public func setActiveAIProvider(_ provider: AIProviderKind) async throws -> AISettings {
        try await sendAuthorized(Request(method: "PUT", path: "me/ai/active", body: encoder.encode(["provider": provider.rawValue])))
    }

    public func testAIProvider(_ provider: AIProviderKind) async throws -> AITestResult {
        try await sendAuthorized(Request(method: "POST", path: "me/ai/\(provider.rawValue)/test", timeout: 45))
    }

    public func aiModels(_ provider: AIProviderKind) async throws -> [String] {
        try await sendAuthorized(Request(method: "GET", path: "me/ai/\(provider.rawValue)/models", timeout: 45))
    }

    /// Отзывает сессию на сервере (если получится) и в любом случае забывает токены.
    public func signOut() async {
        if let tokens = tokenStore.load(),
           let body = try? encoder.encode(RefreshBody(refreshToken: tokens.refreshToken)) {
            _ = try? await perform(Request(method: "POST", path: "auth/logout", body: body), accessToken: nil)
        }
        tokenStore.clear()
    }

    // MARK: - Токены

    private func signIn(path: String, body: SignInBody) async throws -> AuthResponse {
        let response: AuthResponse = try await send(
            Request(method: "POST", path: path, body: encoder.encode(body))
        )
        tokenStore.save(response.tokens)
        return response
    }

    /// Токены новее, чем `stale`. Если обновление уже идёт — ждём его, а не запускаем второе.
    private func refreshedTokens(after stale: AuthTokens) async throws -> AuthTokens {
        if let current = tokenStore.load(), current.accessToken != stale.accessToken {
            return current
        }
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task { try await performRefresh(using: stale.refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh(using refreshToken: String) async throws -> AuthTokens {
        do {
            let response: TokenResponse = try await send(
                Request(method: "POST", path: "auth/refresh", body: encoder.encode(RefreshBody(refreshToken: refreshToken)))
            )
            tokenStore.save(response.tokens)
            return response.tokens
        } catch let error as APIError where error.isUnauthorized {
            tokenStore.clear()
            throw error
        }
    }

    // MARK: - Транспорт

    private func sendAuthorized<T: Decodable>(_ request: Request) async throws -> T {
        try decode(await performAuthorized(request))
    }

    private func sendAuthorizedEmpty(_ request: Request) async throws {
        _ = try await performAuthorized(request)
    }

    private func performAuthorized(_ request: Request) async throws -> Data {
        guard var tokens = tokenStore.load() else { throw APIError.unauthorized(code: nil) }
        if tokens.accessExpiresAt.timeIntervalSinceNow < refreshMargin {
            tokens = try await refreshedTokens(after: tokens)
        }
        let data: Data
        do {
            data = try await perform(request, accessToken: tokens.accessToken)
        } catch let error as APIError where error.isUnauthorized {
            let fresh = try await refreshedTokens(after: tokens)
            data = try await perform(request, accessToken: fresh.accessToken)
        }
        return data
    }

    private func send<T: Decodable>(_ request: Request) async throws -> T {
        try decode(await perform(request, accessToken: nil))
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func perform(_ request: Request, accessToken: String?) async throws -> Data {
        var urlRequest = URLRequest(url: baseURL.appending(path: request.path))
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = request.timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken {
            urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("Invalid response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.detail
            if http.statusCode == 401 {
                throw APIError.unauthorized(code: code)
            }
            throw APIError.server(status: http.statusCode, code: code)
        }
        return data
    }
}

private struct Request: Sendable {
    var method: String
    var path: String
    var body: Data?
    var timeout: TimeInterval = 20
}

private struct SignInBody: Encodable {
    var idToken: String?
    var deviceSecret: String?
    var locale: String?
    var timezone: String?
    var deviceName: String?

    init(idToken: String? = nil, deviceSecret: String? = nil, client: ClientInfo) {
        self.idToken = idToken
        self.deviceSecret = deviceSecret
        locale = client.locale
        timezone = client.timezone
        deviceName = client.deviceName
    }
}

private struct RefreshBody: Encodable {
    var refreshToken: String
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let accessExpiresAt: Date
    let refreshToken: String
    let refreshExpiresAt: Date

    var tokens: AuthTokens {
        AuthTokens(
            accessToken: accessToken,
            accessExpiresAt: accessExpiresAt,
            refreshToken: refreshToken,
            refreshExpiresAt: refreshExpiresAt
        )
    }
}

private struct ErrorBody: Decodable {
    let detail: String
}
