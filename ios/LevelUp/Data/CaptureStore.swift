import Foundation
import LevelUpKit
import Observation

/// Запись, которая не ушла на сервер из-за сети. Отправится позже — ничего не теряется.
struct QueuedCapture: Codable, Identifiable, Hashable {
    var id = UUID()
    var request: CaptureRequest
    var createdAt = Date.now

    static func == (lhs: QueuedCapture, rhs: QueuedCapture) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
@Observable
final class CaptureStore {
    enum SendOutcome {
        case processed(CaptureResult)
        case queued
    }

    private(set) var inbox: [Capture] = []
    private(set) var outbox: [QueuedCapture]
    private(set) var isFlushing = false

    private let api: APIClient
    private let outboxCache = LocalCache<[QueuedCapture]>(name: "capture-outbox")
    var onUnauthorized: () -> Void = {}

    init(api: APIClient) {
        self.api = api
        outbox = outboxCache.load() ?? []
    }

    var pendingCount: Int { inbox.count + outbox.count }

    func send(text: String, source: CaptureSource, autosave: Bool = false) async throws -> SendOutcome {
        let request = CaptureRequest(text: text, source: source, autosave: autosave)
        do {
            let result = try await api.capture(request)
            await loadInbox()
            return .processed(result)
        } catch APIError.network {
            enqueue(request)
            return .queued
        }
    }

    func confirm(_ capture: Capture, items: [CaptureItem]) async throws -> CaptureResult {
        let result = try await api.confirmCapture(id: capture.id, items: items)
        await loadInbox()
        return result
    }

    func retry(_ capture: Capture) async throws -> CaptureResult {
        let result = try await api.retryCapture(id: capture.id)
        await loadInbox()
        return result
    }

    func undo(_ capture: Capture) async throws {
        try await undo(id: capture.id)
    }

    func undo(id: UUID) async throws {
        _ = try await api.undoCapture(id: id)
        await loadInbox()
    }

    func dismiss(_ capture: Capture) async {
        inbox.removeAll { $0.id == capture.id }
        do {
            try await api.dismissCapture(id: capture.id)
        } catch {
            await loadInbox()
        }
    }

    func discard(_ queued: QueuedCapture) {
        outbox.removeAll { $0.id == queued.id }
        outboxCache.save(outbox)
    }

    func loadInbox() async {
        do {
            inbox = try await api.inbox()
        } catch let error as APIError where error.isUnauthorized {
            onUnauthorized()
        } catch {
            // «Входящие» — не критичны: покажем то, что было.
        }
    }

    /// Отправляет то, что накопилось без сети. Результаты появятся во «Входящих» для подтверждения.
    func flushOutbox() async {
        guard !outbox.isEmpty, !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        for queued in outbox {
            do {
                _ = try await api.capture(queued.request)
                discard(queued)
            } catch {
                break  // сети всё ещё нет — попробуем в следующий раз
            }
        }
        await loadInbox()
    }

    func reset() {
        inbox = []
        outbox = []
    }

    private func enqueue(_ request: CaptureRequest) {
        outbox.append(QueuedCapture(request: request))
        outboxCache.save(outbox)
    }
}
