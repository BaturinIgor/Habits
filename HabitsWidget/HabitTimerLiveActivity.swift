import ActivityKit
import SwiftUI
import WidgetKit

/// Таймер привычки на экране блокировки и в Dynamic Island.
struct HabitTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HabitTimerAttributes.self) { context in
            HabitTimerLockView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .padding(16)
                .activitySystemActionForegroundColor(Palette.color(context.attributes.colorIndex))
        } dynamicIsland: { context in
            let color = Palette.color(context.attributes.colorIndex)
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HabitIconView(icon: context.attributes.icon, color: color, size: 40)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HabitTimerText(state: state, isStale: context.isStale)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(color)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.attributes.name)
                            .font(.headline)
                            .lineLimit(1)
                        HabitTimerBar(state: state, isStale: context.isStale, color: color)
                    }
                }
            } compactLeading: {
                HabitIconView(icon: context.attributes.icon, color: color, size: 22)
            } compactTrailing: {
                HabitTimerText(state: state, isStale: context.isStale)
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .frame(maxWidth: 52)
            } minimal: {
                HabitIconView(icon: context.attributes.icon, color: color, size: 22)
            }
        }
    }
}

private struct HabitTimerLockView: View {
    let attributes: HabitTimerAttributes
    let state: HabitTimerAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let color = Palette.color(attributes.colorIndex)
        HStack(spacing: 14) {
            HabitIconView(icon: attributes.icon, color: color, size: 48)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(attributes.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    HabitTimerText(state: state, isStale: isStale)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(color)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120, alignment: .trailing)
                }
                HabitTimerBar(state: state, isStale: isStale, color: color)
            }
        }
    }
}

private struct HabitTimerText: View {
    let state: HabitTimerAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if isStale || state.end <= state.start {
            Image(systemName: "checkmark.circle.fill")
        } else {
            Text(timerInterval: state.start...state.end, countsDown: true)
        }
    }
}

private struct HabitTimerBar: View {
    let state: HabitTimerAttributes.ContentState
    let isStale: Bool
    let color: Color

    var body: some View {
        if isStale || state.end <= state.start {
            ProgressView(value: 1)
                .tint(color)
        } else {
            ProgressView(timerInterval: state.start...state.end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(color)
        }
    }
}
