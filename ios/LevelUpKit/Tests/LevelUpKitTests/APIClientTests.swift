import Foundation
import Synchronization
import Testing
@testable import LevelUpKit

@Suite(.serialized)
struct APIClientTests {
    private let baseURL = URL(string: "https://api.test")!

    init() {
        MockURLProtocol.reset()
    }

    @Test func deviceSignInStoresTokens() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path == "/auth/device")
            return (200, Fixtures.authResponse)
        }
        let store = InMemoryTokenStore()
        let client = makeClient(store)

        let response = try await client.signInWithDevice(
            secret: String(repeating: "s", count: 43),
            client: ClientInfo(locale: "ru", timezone: "Asia/Almaty", deviceName: "iPhone")
        )

        #expect(response.isNewUser)
        #expect(response.user.isGuest)
        #expect(store.load()?.refreshToken == "refresh-1")
    }

    @Test func expiredAccessTokenIsRefreshedOnceForParallelRequests() async throws {
        MockURLProtocol.handler = { request in
            switch request.url?.path {
            case "/auth/refresh": return (200, Fixtures.tokenResponse(access: "access-2"))
            case "/me":
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-2")
                return (200, Fixtures.user)
            default: return (404, Data())
            }
        }
        let store = InMemoryTokenStore(Fixtures.tokens(accessExpiresIn: -10))
        let client = makeClient(store)

        async let first = client.me()
        async let second = client.me()
        _ = try await (first, second)

        #expect(MockURLProtocol.requestCount(path: "/auth/refresh") == 1)
        #expect(store.load()?.accessToken == "access-2")
    }

    @Test func unauthorizedResponseTriggersRefreshAndRetry() async throws {
        MockURLProtocol.handler = { request in
            switch (request.url?.path, request.value(forHTTPHeaderField: "Authorization")) {
            case ("/me", "Bearer access-1"): return (401, Data(#"{"detail":"invalid_access_token"}"#.utf8))
            case ("/me", "Bearer access-2"): return (200, Fixtures.user)
            case ("/auth/refresh", _): return (200, Fixtures.tokenResponse(access: "access-2"))
            default: return (404, Data())
            }
        }
        let client = makeClient(InMemoryTokenStore(Fixtures.tokens(accessExpiresIn: 3600)))

        let user = try await client.me()

        #expect(user.timezone == "Asia/Almaty")
    }

    @Test func rejectedRefreshTokenClearsSession() async throws {
        MockURLProtocol.handler = { _ in (401, Data(#"{"detail":"refresh_token_reused"}"#.utf8)) }
        let store = InMemoryTokenStore(Fixtures.tokens(accessExpiresIn: -10))
        let client = makeClient(store)

        await #expect(throws: APIError.unauthorized(code: "refresh_token_reused")) {
            try await client.me()
        }
        #expect(store.load() == nil)
    }

    @Test func networkFailureDuringRefreshKeepsSession() async throws {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let store = InMemoryTokenStore(Fixtures.tokens(accessExpiresIn: -10))
        let client = makeClient(store)

        await #expect(throws: APIError.self) { try await client.me() }
        #expect(store.load() != nil)
    }

    @Test func deleteTaskAcceptsEmptyResponse() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == "/tasks/9B2B1D7C-6A0E-4A43-9A52-0F3C7C1F6F10")
            return (204, Data())
        }
        let client = makeClient(InMemoryTokenStore(Fixtures.tokens(accessExpiresIn: 3600)))

        try await client.deleteTask(id: UUID(uuidString: "9b2b1d7c-6a0e-4a43-9a52-0f3c7c1f6f10")!)
    }

    @Test func widgetCheckSendsOnlyStatus() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "PATCH")
            let body = try #require(MockURLProtocol.bodyJSON(request))
            #expect(body.keys.sorted() == ["status"])
            #expect(body["status"] as? String == "done")
            return (200, Fixtures.task)
        }
        let client = makeClient(InMemoryTokenStore(Fixtures.tokens(accessExpiresIn: 3600)))

        let task = try await client.setTaskStatus(id: UUID(), status: .done)

        #expect(task.title == "Отчёт")
    }

    @Test func pendingWidgetActionsStayQueuedWithoutNetwork() async throws {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let client = makeClient(InMemoryTokenStore(Fixtures.tokens(accessExpiresIn: 3600)))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = PendingActionStore(file: AppGroupFile(directory: directory, name: "actions.json"))
        store.add(.task(id: UUID(), done: true))
        store.add(.shopping(id: UUID(), bought: true))

        let outcome = await WidgetActionSender.flush(api: client, store: store)

        #expect(outcome.sent == 0)
        #expect(outcome.waiting == 2)
        #expect(store.all().count == 2)
    }

    @Test func latestWidgetActionForItemWins() {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = PendingActionStore(file: AppGroupFile(directory: directory, name: "actions.json"))
        let id = UUID()

        store.add(.task(id: id, done: true))
        store.add(.task(id: id, done: false))

        #expect(store.all() == [.task(id: id, done: false)])
    }

    @Test func financeSummaryAsksForMonth() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path == "/finance/summary")
            #expect(request.url?.query == "month=2026-09")
            return (200, Data("""
            {"month":"2026-09","currency":"KZT","spent":4700.5,"income":0,"spent_today":0,"spent_week":0,
             "week_allowance":null,"expenses_by_category":[{"category":"cafe","amount":4700.5}],
             "income_by_category":[],"by_day":[{"date":"2026-09-03","spent":4700.5,"income":0}],
             "budgets":[],"other_currencies":[]}
            """.utf8))
        }
        let client = makeClient(InMemoryTokenStore(Fixtures.tokens(accessExpiresIn: 3600)))

        let summary = try await client.financeSummary(month: LocalDate(year: 2026, month: 9, day: 17))

        #expect(summary.spent == 4700.5)
        #expect(summary.byDay.first?.date == LocalDate(year: 2026, month: 9, day: 3))
    }

    private func makeClient(_ store: InMemoryTokenStore) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return APIClient(baseURL: baseURL, tokenStore: store, session: URLSession(configuration: configuration))
    }
}

private enum Fixtures {
    static let user = Data("""
    {"id":"6f1c2a8e-9a51-4c3b-8f0a-3c3e2b1d4a5f","display_name":null,"email":null,"avatar_url":null,
     "locale":"ru","timezone":"Asia/Almaty","currency":null,"auth_providers":["device"],
     "created_at":"2026-10-09T18:00:00.123456Z"}
    """.utf8)

    static let authResponse = Data("""
    {"token_type":"bearer","access_token":"access-1","access_expires_at":"2099-01-01T00:00:00Z",
     "refresh_token":"refresh-1","refresh_expires_at":"2099-06-01T00:00:00Z","is_new_user":true,
     "user":\(String(decoding: user, as: UTF8.self))}
    """.utf8)

    static let task = Data("""
    {"id":"9b2b1d7c-6a0e-4a43-9a52-0f3c7c1f6f10","title":"Отчёт","notes":null,
     "status":"done","priority":"normal","due_date":null,"due_time":null,"remind":false,
     "remind_at":null,"reminders":[],"recurrence":null,"difficulty":null,"position":0,
     "completed_at":"2026-10-09T18:00:00Z","capture_id":null,
     "created_at":"2026-10-09T18:00:00Z","updated_at":"2026-10-09T18:00:00Z"}
    """.utf8)

    static func tokenResponse(access: String) -> Data {
        Data("""
        {"token_type":"bearer","access_token":"\(access)","access_expires_at":"2099-01-01T00:00:00Z",
         "refresh_token":"refresh-2","refresh_expires_at":"2099-06-01T00:00:00Z"}
        """.utf8)
    }

    static func tokens(accessExpiresIn seconds: TimeInterval) -> AuthTokens {
        AuthTokens(
            accessToken: "access-1",
            accessExpiresAt: Date(timeIntervalSinceNow: seconds),
            refreshToken: "refresh-1",
            refreshExpiresAt: Date(timeIntervalSinceNow: 86_400)
        )
    }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)

    private static let state = Mutex<(handler: Handler?, paths: [String])>((nil, []))

    static var handler: Handler? {
        get { state.withLock { $0.handler } }
        set { state.withLock { $0.handler = newValue } }
    }

    static func reset() {
        state.withLock { $0 = (nil, []) }
    }

    static func requestCount(path: String) -> Int {
        state.withLock { $0.paths.filter { $0 == path }.count }
    }

    /// Тело запроса: URLSession передаёт его протоколу потоком, а не в httpBody.
    static func bodyJSON(_ request: URLRequest) -> [String: Any]? {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.state.withLock { $0.paths.append(request.url?.path ?? "") }
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}


extension APIClientTests {
    @Test func coachQuestionSendsStableRequestIdentifier() async throws {
        let requestID = UUID()
        MockURLProtocol.handler = { request in
            #expect(request.url?.path == "/coach/questions")
            #expect(request.httpMethod == "POST")
            let body = try #require(MockURLProtocol.bodyJSON(request))
            #expect(body["request_id"] as? String == requestID.uuidString)
            #expect(body["text"] as? String == "Траты?")
            return (200, Data("""
                {"id":"11111111-1111-1111-1111-111111111111","capture_id":"22222222-2222-2222-2222-222222222222",
                 "question":"Траты?","metric":"expense","start_date":"2026-10-01","end_date":"2026-10-12",
                 "value":1700,"currency":"KZT","explanation":"Кафе за октябрь"}
                """.utf8))
        }
        let client = makeClient(InMemoryTokenStore(Fixtures.tokens(accessExpiresIn: 3600)))
        let answer = try await client.askCoach("Траты?", requestID: requestID)
        #expect(answer.value == 1700)
        #expect(answer.currency == "KZT")
    }
}

extension APIClientTests {
    @Test func taskPageSendsFiltersAndDecodesCursor() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path == "/tasks/page")
            let values = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            #expect(values["due"] == "today")
            #expect(values["priority"] == "high")
            #expect(values["q"] == "Отчёт банк")
            #expect(values["cursor"] == "cursor+with/slash=")
            #expect(values["limit"] == "50")
            return (200, Data("{\"items\":[\(String(decoding: Fixtures.task, as: UTF8.self))],\"next_cursor\":\"next\"}".utf8))
        }
        var filter = TaskFilter()
        filter.due = .today
        filter.priority = .high
        let client = makeClient(InMemoryTokenStore(Fixtures.tokens(accessExpiresIn: 3600)))
        let result = try await client.taskPage(TaskPageQuery(filter: filter, search: "Отчёт банк"), cursor: "cursor+with/slash=")
        #expect(result.items.count == 1)
        #expect(result.nextCursor == "next")
        #expect(result.hasMore)
    }

    @MainActor @Test func feedAppendsPagesWithoutDuplicatesAndCachesFirstPage() async throws {
        let other = String(decoding: Fixtures.task, as: UTF8.self).replacingOccurrences(of: "9b2b1d7c-6a0e-4a43-9a52-0f3c7c1f6f10", with: "11111111-1111-1111-1111-111111111111")
        MockURLProtocol.handler = { request in
            let second = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "cursor" } ?? false
            let task = String(decoding: Fixtures.task, as: UTF8.self)
            return (200, Data(second ? "{\"items\":[\(task),\(other)],\"next_cursor\":null}".utf8 : "{\"items\":[\(task)],\"next_cursor\":\"second\"}".utf8))
        }
        let client = makeClient(InMemoryTokenStore(Fixtures.tokens(accessExpiresIn: 3600)))
        let cache = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "feed.json")
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let feed = TaskFeed(api: client, cacheURL: cache)
        await feed.reload(TaskPageQuery())
        #expect(feed.items.count == 1)
        await feed.loadMore()
        #expect(feed.items.count == 2)
        #expect(!feed.hasMore)
        let reopened = TaskFeed(api: client, cacheURL: cache)
        #expect(reopened.items.count == 1)
        #expect(reopened.nextCursor == "second")
    }

    @MainActor @Test func changedQueryCancelsDebounceAndNeverReusesOldCursor() async throws {
        MockURLProtocol.handler = { request in
            let values = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            #expect(values["q"] == "new")
            #expect(values["cursor"] == nil)
            return (200, Data(#"{"items":[],"next_cursor":null}"#.utf8))
        }
        let client = makeClient(InMemoryTokenStore(Fixtures.tokens(accessExpiresIn: 3600)))
        let feed = TaskFeed(api: client)
        let earlier = Task { await feed.reload(TaskPageQuery(search: "old"), debounce: true) }
        try await Task.sleep(for: .milliseconds(20))
        earlier.cancel()
        await feed.reload(TaskPageQuery(search: "new"))
        await earlier.value
        #expect(feed.query?.search == "new")
        #expect(!feed.isLoading)
        #expect(MockURLProtocol.requestCount(path: "/tasks/page") == 1)
    }

    @MainActor @Test func paginationErrorRetainsItemsAndCursorForRetry() async throws {
        MockURLProtocol.handler = { _ in
            (200, Data("{\"items\":[\(String(decoding: Fixtures.task, as: UTF8.self))],\"next_cursor\":\"retry\"}".utf8))
        }
        let client = makeClient(InMemoryTokenStore(Fixtures.tokens(accessExpiresIn: 3600)))
        let feed = TaskFeed(api: client)
        await feed.reload(TaskPageQuery())
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await feed.loadMore()
        #expect(feed.items.count == 1)
        #expect(feed.nextCursor == "retry")
        #expect(!feed.isLoading)
    }
}

extension APIClientTests {
    @MainActor @Test func expiredCursorReloadsCurrentQueryFromFirstPage() async throws {
        MockURLProtocol.handler = { request in
            let cursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "cursor" } ?? false
            if cursor { return (422, Data(#"{"detail":"invalid_task_cursor"}"#.utf8)) }
            return (200, Data("{\"items\":[\(String(decoding: Fixtures.task, as: UTF8.self))],\"next_cursor\":\"cursor\"}".utf8))
        }
        let client = makeClient(InMemoryTokenStore(Fixtures.tokens(accessExpiresIn: 3600)))
        let feed = TaskFeed(api: client)
        await feed.reload(TaskPageQuery())
        await feed.loadMore()
        #expect(MockURLProtocol.requestCount(path: "/tasks/page") == 3)
        #expect(feed.items.count == 1)
        #expect(!feed.isLoading)
    }
}
