import ActivityKit
import Foundation

/// Live Activity тренировки: на экране блокировки (и в Dynamic Island, где он есть) видно
/// текущее упражнение, число подходов и таймер отдыха. Файл собирается и в приложение,
/// и в виджеты: приложение запускает активность, виджеты её рисуют.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exercise: String?
        var setCount: Int
        /// Последний подход: «80 кг × 5».
        var lastSet: String?
        var restEndsAt: Date?
    }

    var startedAt: Date
    var title: String
}
