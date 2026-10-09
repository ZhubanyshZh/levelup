import AppIntents
import LevelUpKit

// Эти интенты открывают приложение сразу в нужном месте. Файл собирается и в приложение,
// и в виджеты: кнопки Пункта управления живут в виджетах, а выполняется интент в приложении.

/// «Записать»: открывает Level Up и сразу начинает запись голосом.
/// Siri не понимает русский, поэтому речь распознаёт само приложение (Apple Speech).
struct OpenVoiceCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Записать голосом"
    static let description = IntentDescription("Открывает Level Up и сразу начинает запись. ИИ сам разложит сказанное по местам.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        RouteCenter.shared.open(.capture(.voice))
        return .result()
    }
}

/// «Дневник»: открывает новую запись в дневнике.
struct OpenJournalEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Запись в дневник"
    static let description = IntentDescription("Открывает новую запись в дневнике.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        RouteCenter.shared.open(.newJournalEntry)
        return .result()
    }
}

/// «Трата»: открывает запись голосом с подсказкой «сколько и на что».
struct OpenExpenseCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Записать трату"
    static let description = IntentDescription("Открывает Level Up и сразу слушает: «такси 3500».")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        RouteCenter.shared.open(.capture(.expense))
        return .result()
    }
}

/// «Тренировка»: продолжить текущую или начать новую.
struct OpenWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Начать тренировку"
    static let description = IntentDescription("Открывает тренировку в Level Up: начать новую или продолжить текущую.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        RouteCenter.shared.open(.workout)
        return .result()
    }
}
