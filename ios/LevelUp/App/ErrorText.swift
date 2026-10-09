import Foundation
import LevelUpKit

/// Человеческий текст для ошибок API. Коды приходят с сервера в поле `detail`.
enum ErrorText {
    static func message(for error: Error) -> String {
        switch error as? APIError {
        case .network:
            String(localized: "Нет связи с сервером. Проверь интернет и попробуй ещё раз.")
        case .unauthorized(code: "invalid_google_token"):
            String(localized: "Google не подтвердил вход. Попробуй ещё раз.")
        case .server(status: 503, code: "google_not_configured"):
            String(localized: "Вход через Google не настроен на сервере.")
        case .server(status: 409, code: "identity_in_use"):
            String(localized: "Этот Google-аккаунт уже привязан к другому профилю Level Up.")
        case .server(_, "coach_busy_conflict"):
            String(localized: "Время занято. Выбери «Добавить без времени».")
        case .server(_, "coach_plan_expired"):
            String(localized: "Время уже прошло. Выбери «Добавить без времени».")
        case .server(_, "coach_task_changed"):
            String(localized: "Эта задача уже выполнена. Открой свежий план.")
        case .server(_, "coach_goal_completed"):
            String(localized: "Цель уже завершена.")
        case .server(_, let code?) where code.hasPrefix("ai_"):
            capture(code)
        default:
            String(localized: "Что-то пошло не так. Попробуй ещё раз.")
        }
    }

    /// Почему ИИ не разобрал запись (поле error_code у записи или ответа проверки ключа).
    static func capture(_ code: String?) -> String {
        switch code {
        case "ai_not_configured":
            String(localized: "ИИ не настроен — добавь ключ в «Ещё → ИИ-помощник».")
        case "ai_invalid_key":
            String(localized: "Ключ ИИ не подходит — проверь его в настройках.")
        case "ai_quota_exceeded":
            String(localized: "У провайдера ИИ закончилась квота или баланс.")
        case "ai_rate_limited":
            String(localized: "Слишком много запросов к ИИ — попробуй через минуту.")
        case "ai_model_not_found":
            String(localized: "Выбранная модель недоступна — выбери другую в настройках.")
        case "ai_key_required":
            String(localized: "Вставь ключ, чтобы подключить провайдера.")
        default:
            String(localized: "ИИ сейчас не ответил. Попробуй ещё раз чуть позже.")
        }
    }

    static func needsAISettings(_ code: String?) -> Bool {
        ["ai_not_configured", "ai_invalid_key", "ai_model_not_found", "ai_quota_exceeded"].contains(code)
    }
}
