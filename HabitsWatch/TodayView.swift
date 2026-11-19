import SwiftUI

/// Главный экран: привычки на сегодня, отметка в одно касание.
struct TodayView: View {
    @Environment(WatchModel.self) private var model
    #if DEBUG
    @State private var timerHabit: UUID? = WatchDesign.openTimer
    #else
    @State private var timerHabit: UUID?
    #endif

    var body: some View {
        content
            .navigationTitle("Today")
            .navigationDestination(item: $timerHabit) { id in
                WatchTimerView(habitID: id)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let day = model.today {
            if day.habits.isEmpty {
                ScrollView {
                    WatchMessageView(symbol: "leaf.fill", text: "No habits today")
                }
            } else {
                list(day)
            }
        } else {
            // Снимка ещё нет или он устарел: данные приходят с iPhone.
            ScrollView {
                WatchMessageView(symbol: "iphone", text: "Open ZenHab on your iPhone to see your habits here.")
            }
        }
    }

    private func list(_ day: WatchDay) -> some View {
        List {
            header(day)
                .listRowBackground(Color.clear)
            ForEach(day.habits) { habit in
                row(habit)
            }
        }
    }

    private func header(_ day: WatchDay) -> some View {
        let done = day.doneCount
        let total = day.plannedCount
        return HStack(spacing: 10) {
            WatchProgressRing(progress: total > 0 ? Double(done) / Double(total) : 0)
                .frame(width: 34, height: 34)
            if total > 0 && done >= total {
                Text("All done!")
                    .font(.headline)
            } else {
                Text("\(done) of \(total)")
                    .font(.headline)
                    .monospacedDigit()
            }
        }
    }

    private func row(_ habit: WatchHabit) -> some View {
        HStack(spacing: 6) {
            Button {
                model.tap(habit)
            } label: {
                HStack(spacing: 8) {
                    WatchHabitIcon(habit: habit, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(habit.name)
                            .font(.system(.body, design: .rounded))
                            .lineLimit(2)
                            .strikethrough(habit.done, color: .secondary)
                            .foregroundStyle(habit.done ? Color.secondary : Color.primary)
                        if habit.target > 1 {
                            Text(verbatim: "\(habit.count)/\(habit.target)")
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 2)
                    WatchCheckMark(habit: habit, size: 26)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(habit.done ? .isSelected : [])

            if habit.timerMinutes != nil && !habit.done {
                Button {
                    timerHabit = habit.id
                } label: {
                    Image(systemName: model.timer?.habitID == habit.id ? "timer.circle.fill" : "timer")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 26, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Timer"))
            }
        }
        .padding(.vertical, 2)
    }
}
