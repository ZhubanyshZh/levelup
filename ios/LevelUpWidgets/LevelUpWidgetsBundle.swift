import SwiftUI
import WidgetKit

@main
struct LevelUpWidgetsBundle: WidgetBundle {
    var body: some Widget {
        QuickCaptureWidget()
        TodayWidget()
        LevelWidget()
        ShoppingWidget()
        JournalWidget()
        CaptureControl()
        JournalControl()
    }
}
