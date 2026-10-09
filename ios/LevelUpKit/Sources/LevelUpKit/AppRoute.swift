import Foundation
import Observation

/// Куда открыть приложение: из виджета, Пункта управления, Siri или команды.
/// Виджеты передают маршрут ссылкой `levelup://…`, кнопки и Siri — через RouteCenter.
public enum AppRoute: Hashable, Sendable {
    public enum CaptureMode: String, Sendable {
        /// expense — сразу слушать, подсказка «сколько и на что».
        case voice, text, expense
    }

    case capture(CaptureMode)
    case newJournalEntry
    case journal
    case shopping
    case today
    case finance
    /// Тренировка: продолжить текущую или начать новую.
    case workout
    case goals
    case goal(UUID)
    case progress
    case coach(CoachKind)

    public static let scheme = "levelup"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .capture(let mode):
            components.host = "capture"
            components.queryItems = [URLQueryItem(name: "mode", value: mode.rawValue)]
        case .newJournalEntry:
            components.host = "journal"
            components.path = "/new"
        case .journal:
            components.host = "journal"
        case .shopping:
            components.host = "shopping"
        case .today:
            components.host = "today"
        case .finance:
            components.host = "finance"
        case .workout:
            components.host = "workout"
        case .goals:
            components.host = "goals"
        case .goal(let id):
            components.host = "goals"
            components.path = "/" + id.uuidString
        case .progress:
            components.host = "progress"
        case .coach(let kind):
            components.host = "coach"
            components.queryItems = [URLQueryItem(name: "kind", value: kind.rawValue)]
        }
        return components.url!
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        switch components.host {
        case "capture":
            let mode = components.queryItems?.first { $0.name == "mode" }?.value
            self = .capture(mode.flatMap(CaptureMode.init(rawValue:)) ?? .voice)
        case "journal":
            self = components.path == "/new" ? .newJournalEntry : .journal
        case "shopping":
            self = .shopping
        case "today":
            self = .today
        case "finance":
            self = .finance
        case "workout":
            self = .workout
        case "goals":
            let id = components.path.split(separator: "/").first.flatMap { UUID(uuidString: String($0)) }
            self = id.map(AppRoute.goal) ?? .goals
        case "progress":
            self = .progress
        case "coach":
            let kind = components.queryItems?.first { $0.name == "kind" }?.value
            self = .coach(kind.flatMap(CoachKind.init(rawValue:)) ?? .current())
        default:
            return nil
        }
    }
}

/// Маршрут, который ждёт, пока приложение его покажет. Кнопки Пункта управления и Siri
/// запускают приложение и кладут сюда, куда открыть.
@MainActor
@Observable
public final class RouteCenter {
    public static let shared = RouteCenter()

    public private(set) var pending: AppRoute?

    public func open(_ route: AppRoute) {
        pending = route
    }

    /// Забрать маршрут для показа (он показывается один раз).
    public func take() -> AppRoute? {
        defer { pending = nil }
        return pending
    }
}
