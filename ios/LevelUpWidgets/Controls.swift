import SwiftUI
import WidgetKit

/// Кнопка Пункта управления «Записать». Её же можно поставить на экран блокировки
/// или на кнопку действия (iPhone 15 Pro и новее).
struct CaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "CaptureControl") {
            ControlWidgetButton(action: OpenVoiceCaptureIntent()) {
                Label("Записать", systemImage: "mic.fill")
            }
        }
        .displayName("Записать")
        .description("Открывает Level Up и сразу начинает запись голосом.")
    }
}

/// Кнопка Пункта управления «Дневник».
struct JournalControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "JournalControl") {
            ControlWidgetButton(action: OpenJournalEntryIntent()) {
                Label("Дневник", systemImage: "book.fill")
            }
        }
        .displayName("Дневник")
        .description("Открывает новую запись в дневнике.")
    }
}
