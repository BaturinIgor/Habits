import SwiftUI

/// Экран таймера привычки: запуск, обратный отсчёт, «Закончить» и «Остановить».
struct HabitTimerView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let habit: Habit
    @State private var timer = HabitTimer.shared
    @State private var finished = 0

    private var color: Color { Palette.color(habit.colorIndex) }
    private var minutes: Int { max(1, habit.timerMinutes ?? 10) }
    private var running: HabitTimer.Running? {
        timer.running.flatMap { $0.habitID == habit.id ? $0 : nil }
    }

    var body: some View {
        analyticsBody.analyticsScreen(.timer)
    }

    @ViewBuilder private var analyticsBody: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    HabitIconView(icon: habit.icon, color: color, size: 36)
                    Text(habit.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                }
                ring
                    .frame(width: 240, height: 240)
                Spacer(minLength: 0)
                buttons
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .uiTestScreen("timer")
            .background(AppBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("sheet.close")
                }
            }
        }
        .presentationDetents([.large])
        .sensoryFeedback(.success, trigger: finished)
        .onChange(of: timer.running) { old, new in
            // Время вышло, пока экран открыт: привычка уже отмечена.
            if old?.habitID == habit.id, new == nil, store.status(habit.id, on: Date()) == .done {
                finished += 1
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var ring: some View {
        if let running {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(0, running.end.timeIntervalSince(context.date))
                ZStack {
                    ProgressRing(progress: 1 - left / max(1, running.duration), lineWidth: 16, color: color)
                    Text(timerInterval: running.start...running.end, countsDown: true)
                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .contentTransition(.numericText(countsDown: true))
                }
            }
        } else {
            ZStack {
                ProgressRing(progress: 0, lineWidth: 16, color: color)
                Text(Self.clock(minutes * 60))
                    .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if running != nil {
            VStack(spacing: 12) {
                Button {
                    Task {
                        await timer.finishNow()
                        finished += 1
                        dismiss()
                    }
                } label: {
                    Label("Finish and check off", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(color)
                .controlSize(.large)
                .accessibilityIdentifier("timer.finish")

                Button(role: .destructive) {
                    Task { await timer.cancel() }
                } label: {
                    Label("Stop timer", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("timer.stop")
            }
        } else {
            VStack(spacing: 12) {
                Button {
                    Task { await timer.start(habit, minutes: minutes) }
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(color)
                .controlSize(.large)
                .accessibilityIdentifier("timer.start")

                Button {
                    store.setStatus(.done, for: habit.id, on: Date(), byUser: true)
                    finished += 1
                    dismiss()
                } label: {
                    Text("Check off without the timer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    /// "10:00" или "1:30:00".
    static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
