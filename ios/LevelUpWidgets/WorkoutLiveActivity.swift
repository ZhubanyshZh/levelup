import ActivityKit
import LevelUpKit
import SwiftUI
import WidgetKit

/// Тренировка на экране блокировки: упражнение, подходы и таймер отдыха.
/// На iPhone без Dynamic Island видна только плашка на экране блокировки.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(context: context)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(AppRoute.workout.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.exercise ?? context.attributes.title)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "figure.strengthtraining.traditional")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(Brand.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(context: context)
                        .font(.title3.monospacedDigit().bold())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SetsLine(state: context.state)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(Brand.accent)
            } compactTrailing: {
                TimerText(context: context)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(Brand.accent)
            }
            .widgetURL(AppRoute.workout.url)
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    private var isResting: Bool {
        guard let rest = context.state.restEndsAt else { return false }
        return rest > .now && !context.isStale
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Brand.accent.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.exercise ?? context.attributes.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                SetsLine(state: context.state)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(isResting ? "Отдых" : "Идёт")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                TimerText(context: context)
                    .font(.title2.monospacedDigit().bold())
                    .foregroundStyle(isResting ? Brand.accent : .white)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

/// Пока идёт отдых — обратный отсчёт, иначе — сколько длится тренировка.
private struct TimerText: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        if let rest = context.state.restEndsAt, rest > .now, !context.isStale {
            Text(timerInterval: Date.now...rest, countsDown: true)
        } else {
            Text(context.attributes.startedAt, style: .timer)
        }
    }
}

private struct SetsLine: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if let last = state.lastSet {
            Text("Подходов: \(state.setCount) · \(last)")
        } else {
            Text("Подходов: \(state.setCount)")
        }
    }
}
