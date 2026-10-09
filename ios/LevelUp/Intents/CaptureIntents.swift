import AppIntents
import Foundation
import LevelUpKit

/// «Добавить в Level Up» без открытия приложения: текст из Команд, Siri (на её языке)
/// или касания сзади. Сохраняется сразу, без карточек; отменить — «Отменить запись».
///
/// Окно с вопросом «Что записать?» iOS показывает на языке Siri, а русского у Siri нет —
/// поэтому вопрос будет по-английски. Ответ после сохранения — на языке приложения.
struct AddCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Добавить запись"
    static let description = IntentDescription(
        "Разбирает текст и сразу сохраняет задачи, покупки и записи в дневник — приложение открывать не нужно."
    )

    @Parameter(title: "Текст", requestValueDialog: "Что записать?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Добавить \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return .result(dialog: "Пустая запись — нечего добавить.")
        }
        guard let store = await AppEnvironment.session.signedInStore() else {
            return .result(dialog: "Сначала открой Level Up и войди.")
        }
        let outcome = try await store.captures.send(text: value, source: .siri, autosave: true)
        switch outcome {
        case .queued:
            return .result(dialog: "Нет связи с сервером. Запись сохранена на телефоне и отправится сама.")
        case .processed(let result):
            store.apply(result)
            LastSiriCapture.save(result.capture.id)
            return .result(dialog: IntentDialog(stringLiteral: CaptureSummary.spoken(result)))
        }
    }
}

/// «Отменить последнюю запись»: убирает всё, что создала последняя запись через Siri или команду.
struct UndoLastCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Отменить последнюю запись"
    static let description = IntentDescription("Удаляет задачи, покупки и записи дневника, добавленные последней записью через Siri или команду.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let id = LastSiriCapture.load() else {
            return .result(dialog: "Нечего отменять.")
        }
        guard let store = await AppEnvironment.session.signedInStore() else {
            return .result(dialog: "Сначала открой Level Up и войди.")
        }
        do {
            try await store.captures.undo(id: id)
        } catch APIError.server(status: 409, _) {
            LastSiriCapture.clear()
            return .result(dialog: "Эта запись уже отменена.")
        }
        LastSiriCapture.clear()
        await store.refreshAll()
        return .result(dialog: "Отменил последнюю запись.")
    }
}

struct LevelUpShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenVoiceCaptureIntent(),
            phrases: [
                "Запиши в \(.applicationName)",
                "Записать в \(.applicationName)",
                "Новая запись в \(.applicationName)",
            ],
            shortTitle: "Записать",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: AddCaptureIntent(),
            phrases: [
                "Добавь в \(.applicationName)",
                "Добавить в \(.applicationName)",
            ],
            shortTitle: "Добавить текстом",
            systemImageName: "text.badge.plus"
        )
        AppShortcut(
            intent: OpenJournalEntryIntent(),
            phrases: [
                "Дневник в \(.applicationName)",
                "Запиши день в \(.applicationName)",
            ],
            shortTitle: "Дневник",
            systemImageName: "book"
        )
        AppShortcut(
            intent: UndoLastCaptureIntent(),
            phrases: [
                "Отмени последнюю запись в \(.applicationName)",
            ],
            shortTitle: "Отменить запись",
            systemImageName: "arrow.uturn.backward"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .purple
}

/// Короткий итог записи — на экране после сохранения и в ответе Siri.
enum CaptureSummary {
    static func text(of result: CaptureResult) -> String {
        var parts: [String] = []
        if !result.tasks.isEmpty {
            parts.append(String(localized: "Задач: \(result.tasks.count)"))
        }
        if !result.facts.isEmpty {
            parts.append(String(localized: "Фактов о тебе: \(result.facts.count)"))
        }
        if !result.journal.isEmpty {
            parts.append(String(localized: "Записей в дневнике: \(result.journal.count)"))
        }
        if !result.shopping.isEmpty {
            parts.append(String(localized: "Покупок: \(result.shopping.count)"))
        }
        if result.xpGained > 0 {
            parts.append("+\(result.xpGained) XP")
        }
        let waiting = result.capture.items.filter { $0.include && !$0.supported }.count
        if waiting > 0 {
            parts.append(String(localized: "ждут во «Входящих»: \(waiting)"))
        }
        return parts.isEmpty ? String(localized: "Ничего не добавлено.") : parts.joined(separator: " · ")
    }

    /// Ответ Siri: что сохранено, или почему запись ждёт во «Входящих».
    static func spoken(_ result: CaptureResult) -> String {
        switch result.capture.status {
        case .failed:
            String(localized: "Сохранил во «Входящие». \(ErrorText.capture(result.capture.errorCode))")
        case .confirmed, .deferred:
            String(localized: "Готово. \(text(of: result))")
        case .parsed, .undone:
            String(localized: "Сохранил во «Входящие».")
        }
    }
}

/// Последняя запись через Siri или команду — чтобы её можно было отменить голосом.
enum LastSiriCapture {
    private static let key = "levelup.lastSiriCapture"

    static func save(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: key)
    }

    static func load() -> UUID? {
        UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
