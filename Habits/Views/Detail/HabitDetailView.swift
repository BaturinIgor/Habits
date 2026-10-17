import Charts
import SwiftUI
import UIKit

struct HabitDetailView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let habitID: UUID

    @State private var month: Date = Calendar.app.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var editingHabit: Habit?
    @State private var noteTarget: NoteTarget?

    var body: some View {
        Group {
            if let habit = store.habit(habitID) {
                content(habit)
            } else {
                ContentUnavailableView("Habit deleted", systemImage: "trash")
            }
        }
        .background(AppBackground())
        .onChange(of: store.habit(habitID) == nil) { _, removed in
            if removed { dismiss() }
        }
    }

    private func content(_ habit: Habit) -> some View {
        let color = Palette.color(habit.colorIndex)
        let stats = Stats.habit(habit, in: store.data)
        return ScrollView {
            VStack(spacing: 16) {
                header(habit, color: color)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    StatTile(title: "Current streak", value: stats.isWeekly ? Fmt.weeks(stats.currentStreak) : Fmt.days(stats.currentStreak), systemImage: "flame.fill", color: .orange)
                    StatTile(title: "Best streak", value: stats.isWeekly ? Fmt.weeks(stats.bestStreak) : Fmt.days(stats.bestStreak), systemImage: "trophy.fill", color: .yellow)
                    StatTile(title: "Completion", value: "\(Int((stats.completionRate * 100).rounded()))%", systemImage: "chart.pie.fill", color: color)
                    StatTile(title: "Total check-ins", value: "\(stats.totalDone)", systemImage: "checkmark.circle.fill", color: .green)
                }

                MonthCalendarCard(habit: habit, month: $month) { day in
                    noteTarget = NoteTarget(habitID: habit.id, day: DayKey.make(day))
                }

                if habit.schedule.kind != .once {
                    WeeklyChartCard(habit: habit, data: store.data)
                }

                NotesCard(habit: habit, data: store.data) { day in
                    noteTarget = NoteTarget(habitID: habit.id, day: day)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editingHabit = habit }
            }
        }
        .sheet(item: $editingHabit) { habit in
            HabitEditorView(habit: habit)
        }
        .sheet(item: $noteTarget) { target in
            NoteEditorView(target: target)
        }
    }

    private func header(_ habit: Habit, color: Color) -> some View {
        VStack(spacing: 12) {
            HabitIconView(icon: habit.icon, color: color, size: 84)
                .shadow(color: color.opacity(0.35), radius: 16, y: 8)
            VStack(spacing: 4) {
                Text(habit.name)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                if !habit.details.isEmpty {
                    Text(habit.details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            HStack(spacing: 8) {
                chip(habit.scheduleSummary, systemImage: "calendar")
                if let reminder = habit.reminder {
                    chip(reminder.text, systemImage: "bell.fill")
                }
                if habit.isArchived {
                    chip(String(localized: "Archived"), systemImage: "archivebox.fill")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }
}

// MARK: - Календарь месяца

struct MonthCalendarCard: View {
    @Environment(HabitStore.self) private var store
    let habit: Habit
    @Binding var month: Date
    var onNote: (Date) -> Void

    private let calendar = Calendar.app
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private struct Cell: Identifiable {
        let id: Int
        let date: Date?
    }

    private var cells: [Cell] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let first = interval.start
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var result: [Cell] = (0..<leading).map { Cell(id: -($0 + 1), date: nil) }
        for d in 0..<count {
            result.append(Cell(id: d, date: calendar.date(byAdding: .day, value: d, to: first)))
        }
        return result
    }

    var body: some View {
        let color = Palette.color(habit.colorIndex)
        VStack(spacing: 14) {
            HStack {
                Text(Fmt.monthYear(month))
                    .font(.headline)
                    .contentTransition(.numericText())
                Spacer()
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                Button { shift(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }

            HStack(spacing: 4) {
                ForEach(Weekdays.ordered, id: \.self) { weekday in
                    Text(Weekdays.short(weekday))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(cells) { cell in
                    if let date = cell.date {
                        dayCell(date, color: color)
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }

            HStack(spacing: 14) {
                legend(color: color, title: "Completed", filled: true)
                legend(color: .secondary, title: "Skipped", filled: false)
                legend(color: .red.opacity(0.5), title: "Missed", filled: true)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text("Tap a day to check it off. Press and hold to skip it or add a note.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card()
    }

    private func shift(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: month) {
            withAnimation(.snappy) { month = next }
        }
    }

    @ViewBuilder
    private func dayCell(_ date: Date, color: Color) -> some View {
        let key = DayKey.make(date, calendar: calendar)
        let today = calendar.startOfDay(for: Date())
        let scheduled = habit.isScheduled(on: date, calendar: calendar)
        let isFuture = date > today
        let isToday = calendar.isDate(date, inSameDayAs: today)
        let status = store.data.status(habit.id, day: key)
        let hasNote = !store.data.note(habit.id, day: key).isEmpty
        let isMissed = scheduled && status == nil && date < today && habit.schedule.kind != .weekly
        let canEdit = scheduled && !isFuture

        ZStack {
            if status == .done {
                Circle().fill(color.gradient)
            } else if status == .skipped {
                Circle().strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            } else if isMissed {
                Circle().fill(Color.red.opacity(0.12))
            } else if scheduled {
                Circle().strokeBorder(color.opacity(0.35), lineWidth: 1.5)
            }
            if isToday && status != .done {
                Circle().strokeBorder(color, lineWidth: 2)
            }
            Text("\(calendar.component(.day, from: date))")
                .font(.callout.weight(isToday ? .bold : .medium))
                .foregroundStyle(status == .done ? Color.white : (scheduled ? Color.primary : Color.secondary.opacity(0.45)))
            if hasNote {
                Circle()
                    .fill(status == .done ? Color.white : color)
                    .frame(width: 4, height: 4)
                    .offset(y: 13)
            }
        }
        .frame(height: 38)
        .contentShape(Circle())
        .onTapGesture {
            guard canEdit else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                store.toggleDone(habit.id, on: date)
            }
        }
        .contextMenu {
            if canEdit {
                Button {
                    store.setStatus(.done, for: habit.id, on: date)
                } label: { Label("Mark as done", systemImage: "checkmark.circle") }
                Button {
                    store.setStatus(.skipped, for: habit.id, on: date)
                } label: { Label("Skipped", systemImage: "forward") }
                Button {
                    store.setStatus(nil, for: habit.id, on: date)
                } label: { Label("Reset", systemImage: "arrow.uturn.backward") }
                Divider()
                Button {
                    onNote(date)
                } label: { Label(hasNote ? String(localized: "Edit note") : String(localized: "Note"), systemImage: "note.text") }
            }
        }
        .sensoryFeedback(.selection, trigger: status)
    }

    private func legend(color: Color, title: LocalizedStringKey, filled: Bool) -> some View {
        HStack(spacing: 5) {
            if filled {
                Circle().fill(color).frame(width: 8, height: 8)
            } else {
                Circle().strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: [2, 2])).frame(width: 8, height: 8)
            }
            Text(title)
        }
    }
}

// MARK: - График по неделям

struct WeeklyChartCard: View {
    let habit: Habit
    let data: AppData

    var body: some View {
        let color = Palette.color(habit.colorIndex)
        let points = Stats.weeklyRates(habit, in: data, weeks: 12)
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 12 weeks")
                .font(.headline)
            Chart(points) { point in
                BarMark(
                    x: .value("Week", point.weekStart, unit: .weekOfYear, calendar: Calendar.app),
                    y: .value("Completion", point.hasData ? point.rate * 100 : 0)
                )
                .foregroundStyle(color.gradient)
                .cornerRadius(6)
            }
            .chartYScale(domain: 0.0...100.0)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0.0, 50.0, 100.0]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text("\(Int(number))%")
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(Fmt.shortDate(date))
                        }
                    }
                }
            }
            .frame(height: 170)
        }
        .card()
    }
}

// MARK: - Заметки

struct NotesCard: View {
    let habit: Habit
    let data: AppData
    var onOpen: (String) -> Void

    var body: some View {
        let notes = data.notes(for: habit.id)
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes")
                .font(.headline)
            if notes.isEmpty {
                Text("Nothing yet. Add a note by pressing and holding a habit on the Today screen or a day in the calendar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(notes) { item in
                    Button {
                        onOpen(item.day)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(DayKey.date(item.day).map { Fmt.relativeDay($0) } ?? item.day)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(item.note)
                                .font(.subheadline)
                                .foregroundStyle(Color.primary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.fill.quaternary))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
