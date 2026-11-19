import SwiftUI

/// Таймер привычки (Pro): обратный отсчёт и отметка, когда время вышло.
struct WatchTimerView: View {
    @Environment(WatchModel.self) private var model
    let habitID: UUID

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let habit = model.habit(habitID) {
                    HStack(spacing: 6) {
                        WatchHabitIcon(habit: habit, size: 22)
                        Text(habit.name)
                            .font(.headline)
                            .lineLimit(2)
                    }
                    if !model.isPro {
                        locked
                    } else if habit.done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(WatchPalette.color(habit.colorIndex))
                        Text("Time's up. Well done!")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    } else if let run = model.timer, run.habitID == habitID {
                        running(run, habit: habit)
                    } else {
                        idle(habit)
                    }
                } else {
                    WatchMessageView(symbol: "iphone", text: "Open ZenHab on your iPhone to see your habits here.")
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Timer")
        .task(id: model.timer) {
            // Ждём конца отсчёта, пока экран открыт.
            guard let run = model.timer else { return }
            let delay = run.end.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            model.checkTimer()
        }
    }

    private var locked: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 26))
                .foregroundStyle(.tint)
            Text("Available with Pro")
                .font(.headline)
            Text("Get Pro on your iPhone to use the timer on Apple Watch.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private func idle(_ habit: WatchHabit) -> some View {
        VStack(spacing: 8) {
            Text("\(habit.timerMinutes ?? 0) min")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
            Button {
                model.startTimer(habit)
            } label: {
                Label("Start timer", systemImage: "play.fill")
            }
            .tint(WatchPalette.color(habit.colorIndex))
            Button("Check off without the timer") {
                model.complete(habit)
            }
            .font(.footnote)
        }
    }

    private func running(_ run: WatchTimerRun, habit: WatchHabit) -> some View {
        VStack(spacing: 8) {
            Text(timerInterval: run.start...run.end, countsDown: true)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.center)
            ProgressView(timerInterval: run.start...run.end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(WatchPalette.color(habit.colorIndex))
            Button {
                model.finishTimer()
            } label: {
                Label("Finish and check off", systemImage: "checkmark")
            }
            .tint(WatchPalette.color(habit.colorIndex))
            Button(role: .destructive) {
                model.stopTimer()
            } label: {
                Label("Stop timer", systemImage: "stop.fill")
            }
        }
    }
}
