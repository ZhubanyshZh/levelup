import SwiftUI
import WidgetKit

@main
struct LevelUpWidgetsBundle: WidgetBundle {
    var body: some Widget {
        QuickCaptureWidget()
        TodayWidget()
        LevelWidget()
        QuestsWidget()
        GoalWidget()
        FinanceWidget()
        WorkoutWidget()
        ShoppingWidget()
        JournalWidget()
        WorkoutLiveActivity()
        CaptureControl()
        ExpenseControl()
        JournalControl()
        WorkoutControl()
    }
}
