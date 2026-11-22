import Charts
import SwiftUI

// MARK: - Карточка на экране «Сегодня»

/// Отметка настроения одним касанием. После оценки карточка сворачивается в строку.
struct MoodCard: View {
    @Environment(HabitStore.self) private var store
    let dayKey: String
    let isToday: Bool
    let openJournal: () -> Void
    let edit: () -> Void

    var body: some View {
        let entry = store.mood(on: dayKey)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(isToday ? LocalizedStringKey("How are you today?") : LocalizedStringKey("How was your day?"))
                    .font(.headline)
                Spacer(minLength: 0)
                Button(action: openJournal) {
                    HStack(spacing: 4) {
                        Text("Journal")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("mood.journal")
            }
            if let entry {
                Button(action: edit) {
                    HStack(spacing: 12) {
                        let level = MoodLevel(clamping: entry.level)
                        Text(verbatim: level.emoji)
                            .font(.system(size: 34))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(level.title)
                                .font(.subheadline.weight(.semibold))
                            Text(entry.note ?? String(localized: "Add a note"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "pencil")
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(Color.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 0) {
                    ForEach(MoodLevel.allCases) { level in
                        Button {
                            withAnimation(.snappy) {
                                store.setMood(level.rawValue, dayKey: dayKey)
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            VStack(spacing: 4) {
                                Text(verbatim: level.emoji)
                                    .font(.system(size: 32))
                                Text(level.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.9))
                        .accessibilityLabel(Text(level.title))
                        .accessibilityIdentifier("mood.level.\(level.rawValue)")
                    }
                }
            }
        }
        .card(padding: 14, cornerRadius: 22)
    }
}

// MARK: - Запись за день

/// День, запись которого открыта в редакторе.
struct MoodDay: Identifiable, Hashable {
    let key: String
    var id: String { key }
}

/// Выбор оценки и заметка за день.
struct MoodEntryEditor: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let dayKey: String

    @State private var level: MoodLevel = .okay
    @State private var note = ""
    @FocusState private var focused: Bool

    var body: some View {
        analyticsBody.analyticsScreen(.moodEditor)
    }

    @ViewBuilder private var analyticsBody: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(DayKey.date(dayKey).map { Fmt.relativeDay($0) } ?? dayKey)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    ForEach(MoodLevel.allCases) { item in
                        Button {
                            withAnimation(.snappy) { level = item }
                        } label: {
                            VStack(spacing: 4) {
                                Text(verbatim: item.emoji)
                                    .font(.system(size: item == level ? 40 : 30))
                                    .opacity(item == level ? 1 : 0.45)
                                Text(item.title)
                                    .font(.caption2.weight(item == level ? .semibold : .regular))
                                    .foregroundStyle(item == level ? Color.primary : .secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(item.title))
                        .accessibilityAddTraits(item == level ? .isSelected : [])
                    }
                }
                ZStack(alignment: .topLeading) {
                    if note.isEmpty {
                        Text("What happened today? What helped?")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 17)
                            .padding(.vertical, 20)
                    }
                    TextEditor(text: $note)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                }
                .frame(minHeight: 140)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.fill.tertiary))
                if store.mood(on: dayKey) != nil {
                    Button(role: .destructive) {
                        store.removeMood(dayKey: dayKey)
                        dismiss()
                    } label: {
                        Label("Delete entry", systemImage: "trash")
                            .font(.subheadline)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(AppBackground())
            .navigationTitle("Mood")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.setMood(level.rawValue, note: note, dayKey: dayKey)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let entry = store.mood(on: dayKey) {
                    level = MoodLevel(clamping: entry.level)
                    note = entry.note ?? ""
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Дневник

/// История настроения. Без Pro видны последние 7 дней, график за месяц и связь с привычками в Pro.
struct MoodJournalView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editing: MoodDay?
    @State private var showingPaywall = false

    var body: some View {
        analyticsBody.analyticsScreen(.moodJournal)
    }

    @ViewBuilder private var analyticsBody: some View {
        let items = MoodJournal.items(in: store.data)
        let isPro = store.data.isPro
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if items.isEmpty {
                        EmptyStateView(
                            systemImage: "face.smiling",
                            title: "No entries yet",
                            message: "Rate your mood on the Today screen once a day. After a couple of weeks you'll see which habits lift it."
                        )
                    } else {
                        summaryCard
                        insightsCard(isPro: isPro)
                        entriesCard(items, isPro: isPro)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle("Mood journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editing = MoodDay(key: DayKey.make(Date()))
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Today's entry")
                }
            }
            .sheet(item: $editing) { day in
                MoodEntryEditor(dayKey: day.key)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(highlight: .mood)
            }
        }
    }

    private var summaryCard: some View {
        let week = MoodJournal.average(in: store.data, days: 7)
        let month = MoodJournal.average(in: store.data, days: 30)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                average(week, title: String(localized: "Last 7 days"))
                average(month, title: String(localized: "Last 30 days"))
            }
            if store.data.isPro {
                MoodChart(points: chartPoints)
                    .frame(height: 150)
            }
        }
        .card(padding: 16, cornerRadius: 22)
    }

    private func average(_ value: Double?, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let value {
                let level = MoodLevel(clamping: Int(value.rounded()))
                HStack(spacing: 6) {
                    Text(verbatim: level.emoji).font(.title2)
                    Text(value, format: .number.precision(.fractionLength(1)))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                }
            } else {
                Text(verbatim: "—").font(.title2.weight(.bold))
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chartPoints: [MoodChart.Point] {
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: Date())
        return (0..<30).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today),
                  let entry = store.mood(on: DayKey.make(date)) else { return nil }
            return MoodChart.Point(date: date, level: entry.level)
        }
        .reversed()
    }

    /// Инсайты (KAN-137, Pro): топ-3 привычки, в дни с которыми настроение в среднем выше.
    /// Без Pro - заголовок и замок, как и раньше: остальной дневник частично бесплатный.
    @ViewBuilder
    private func insightsCard(isPro: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("What goes with a better mood")
                    .font(.headline)
                if !isPro { ProBadge() }
            }
            if isPro {
                switch MoodJournal.insights(in: store.data) {
                case .ready(let impacts):
                    ForEach(impacts) { impact in
                        HStack(spacing: 12) {
                            HabitIconView(icon: impact.habit.icon, color: Palette.color(impact.habit.colorIndex), size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(impact.habit.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("On days with this habit, your mood is higher on average")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Text(impact.delta, format: .number.precision(.fractionLength(1)).sign(strategy: .always()))
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.green)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text("This is a pattern in your entries, not proof that the habit is the cause.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                case .needMoreDays(let days):
                    Label {
                        Text("Rate your mood for \(Fmt.days(days)) more to see which habits go with your better days.")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "hourglass")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("mood.insights.needMore")
                case .noLift:
                    Text("No habit stands out yet: your mood is about the same on days with and without them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Button {
                    showingPaywall = true
                } label: {
                    Label("See which habits go with your better days", systemImage: "lock.fill")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16, cornerRadius: 22)
        .accessibilityIdentifier("mood.insights")
    }

    private func entriesCard(_ items: [MoodJournal.Item], isPro: Bool) -> some View {
        let visible = isPro ? items : items.filter { MoodJournal.isFree($0.date) }
        let hidden = items.count - visible.count
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(visible) { item in
                Button {
                    editing = MoodDay(key: item.day)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text(verbatim: item.level.emoji)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fmt.relativeDay(item.date))
                                .font(.subheadline.weight(.semibold))
                            if let note = item.entry.note {
                                Text(note)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            } else {
                                Text(item.level.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .foregroundStyle(Color.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if item.id != visible.last?.id || hidden > 0 {
                    Divider()
                }
            }
            if hidden > 0 {
                Button {
                    showingPaywall = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                        Text("Older entries: \(hidden). Your full history is in Pro.")
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        ProBadge()
                    }
                    .font(.subheadline)
                    .padding(.vertical, 12)
                }
            }
        }
        .card(padding: 16, cornerRadius: 22)
    }
}

/// График настроения за последние 30 дней.
struct MoodChart: View {
    struct Point: Identifiable {
        let date: Date
        let level: Int
        var id: Date { date }
    }

    let points: [Point]

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Day", point.date, unit: .day), y: .value("Mood", point.level))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.accentColor.gradient)
            PointMark(x: .value("Day", point.date, unit: .day), y: .value("Mood", point.level))
                .foregroundStyle(MoodLevel(clamping: point.level).color)
        }
        .chartYScale(domain: 1...5)
        .chartYAxis {
            AxisMarks(values: [1, 3, 5]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let level = value.as(Int.self) {
                        Text(verbatim: MoodLevel(clamping: level).emoji)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
    }
}
