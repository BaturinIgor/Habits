import Charts
import SwiftUI
import UIKit

struct StatsView: View {
    @Environment(HabitStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if store.data.activeHabits.isEmpty {
                        EmptyStateView(
                            systemImage: "chart.bar.fill",
                            title: "Nothing to count yet",
                            message: "Statistics will appear once you start checking off habits."
                        )
                    } else {
                        summary
                        WeekChartCard(days: Stats.lastDays(7, in: store.data))
                        HeatmapCard(data: store.data)
                        habitsCard
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Statistics")
            .navigationDestination(for: UUID.self) { id in
                HabitDetailView(habitID: id)
            }
        }
    }

    private var summary: some View {
        let data = store.data
        let allStats = data.activeHabits.map { Stats.habit($0, in: data) }
        let today = Stats.day(Date(), in: data)
        let rate30 = Stats.overallRate(days: 30, in: data)
        let bestCurrent = allStats.map(\.currentStreak).max() ?? 0
        let totalDone = allStats.map(\.totalDone).reduce(0, +)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(title: "Today", value: String(localized: "\(today.done) of \(today.total)"), systemImage: "checkmark.circle.fill", color: .accentColor)
            StatTile(title: "Last 30 days", value: "\(Int((rate30 * 100).rounded()))%", systemImage: "chart.pie.fill", color: .green)
            StatTile(title: "Best current streak", value: Fmt.days(bestCurrent), systemImage: "flame.fill", color: .orange)
            StatTile(title: "Total check-ins", value: "\(totalDone)", systemImage: "star.fill", color: .yellow)
        }
    }

    private var habitsCard: some View {
        let data = store.data
        return VStack(alignment: .leading, spacing: 14) {
            Text("By habit")
                .font(.headline)
            ForEach(data.activeHabits) { habit in
                let stats = Stats.habit(habit, in: data)
                let color = Palette.color(habit.colorIndex)
                NavigationLink(value: habit.id) {
                    HStack(spacing: 12) {
                        HabitIconView(icon: habit.icon, color: color, size: 38)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(habit.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                Spacer()
                                if stats.currentStreak > 0 {
                                    Label("\(stats.currentStreak)", systemImage: "flame.fill")
                                        .labelStyle(CompactLabelStyle())
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.orange)
                                }
                                Text("\(Int((stats.completionRate * 100).rounded()))%")
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: stats.completionRate)
                                .tint(color)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .card()
    }
}

// MARK: - Неделя

struct WeekChartCard: View {
    let days: [DayProgress]

    private struct Bar: Identifiable {
        let id: String
        let label: String
        let kind: String
        let value: Int
    }

    private var bars: [Bar] {
        days.flatMap { day -> [Bar] in
            let label = Fmt.weekdayShort(day.date)
            let key = DayKey.make(day.date)
            return [
                Bar(id: key + "d", label: label, kind: String(localized: "Completed"), value: day.done),
                Bar(id: key + "r", label: label, kind: String(localized: "Remaining"), value: max(0, day.total - day.done))
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 days")
                .font(.headline)
            Chart(bars) { bar in
                BarMark(
                    x: .value("Day", bar.label),
                    y: .value("Habits", bar.value)
                )
                .foregroundStyle(by: .value("Status", bar.kind))
                .cornerRadius(6)
            }
            .chartForegroundStyleScale([
                String(localized: "Completed"): Color.accentColor,
                String(localized: "Remaining"): Color.gray.opacity(0.25)
            ])
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 180)
        }
        .card()
    }
}

// MARK: - Тепловая карта

struct HeatmapCard: View {
    let data: AppData
    private let weeks = 16
    private let calendar = Calendar.app

    var body: some View {
        let today = calendar.startOfDay(for: Date())
        let thisWeek = Stats.startOfWeek(today, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: thisWeek) ?? thisWeek

        VStack(alignment: .leading, spacing: 12) {
            Text("Activity over \(weeks) weeks")
                .font(.headline)
            HStack(alignment: .top, spacing: 4) {
                VStack(spacing: 4) {
                    ForEach(Weekdays.ordered, id: \.self) { weekday in
                        Text(Weekdays.short(weekday))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 18)
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { d in
                            let date = calendar.date(byAdding: .day, value: w * 7 + d, to: start) ?? start
                            cell(date: date, today: today)
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("Less")
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(level == 0 ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(Color.accentColor.opacity(0.2 + 0.8 * level)))
                        .frame(width: 11, height: 11)
                }
                Text("More")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .card()
    }

    @ViewBuilder
    private func cell(date: Date, today: Date) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        if date > today {
            shape.fill(Color.clear)
                .aspectRatio(1, contentMode: .fit)
        } else {
            let progress = Stats.day(date, in: data, calendar: calendar)
            shape
                .fill(progress.total == 0 || progress.done == 0
                      ? AnyShapeStyle(.fill.tertiary)
                      : AnyShapeStyle(Color.accentColor.opacity(0.2 + 0.8 * progress.fraction)))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if calendar.isDate(date, inSameDayAs: today) {
                        shape.strokeBorder(Color.primary.opacity(0.5), lineWidth: 1)
                    }
                }
        }
    }
}
