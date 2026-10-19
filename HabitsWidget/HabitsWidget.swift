import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Данные виджета

struct WidgetHabit: Identifiable, Hashable {
    let id: UUID
    let name: String
    let icon: HabitIcon
    let colorIndex: Int
    let status: CheckStatus?
    let time: String?
    var progress: Double = 0
    var countText: String? = nil
    /// Привычки "N раз в неделю" входят в итог дня, только если их сделали.
    var countsInTotal: Bool = true
    /// Недельная цель уже выполнена, привычку не нужно предлагать.
    var goalMet: Bool = false
}

struct HabitsEntry: TimelineEntry {
    let date: Date
    let dayKey: String
    let items: [WidgetHabit]

    var done: Int { items.filter { $0.status == .done }.count }
    var total: Int { items.filter { $0.status != .skipped && ($0.countsInTotal || $0.status == .done) }.count }
    var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }
    var pending: [WidgetHabit] { items.filter { $0.status == nil && !$0.goalMet } }

    static var sample: HabitsEntry {
        HabitsEntry(
            date: Date(),
            dayKey: DayKey.make(Date()),
            items: [
                WidgetHabit(id: UUID(), name: String(localized: "Drink water"), icon: .symbol("drop.fill"), colorIndex: 5, status: .done, time: "09:00"),
                WidgetHabit(id: UUID(), name: String(localized: "Walk"), icon: .symbol("figure.walk"), colorIndex: 3, status: nil, time: "13:00"),
                WidgetHabit(id: UUID(), name: String(localized: "Reading"), icon: .symbol("book.fill"), colorIndex: 7, status: nil, time: "21:00")
            ]
        )
    }
}

struct HabitsProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitsEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitsEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
        } else {
            completion(Self.entry(for: Date(), data: DataFile.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitsEntry>) -> Void) {
        let data = DataFile.load()
        let calendar = Calendar.app
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        let entries = [
            Self.entry(for: now, data: data),
            Self.entry(for: tomorrow, data: data)
        ]
        completion(Timeline(entries: entries, policy: .after(tomorrow.addingTimeInterval(60))))
    }

    static func entry(for date: Date, data: AppData) -> HabitsEntry {
        let calendar = Calendar.app
        let key = DayKey.make(date, calendar: calendar)
        let ordered = todaySections(data.habits(on: date, calendar: calendar), data: data, day: key).flatMap(\.habits)
        let position = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0) })
        let items = ordered
            .map { habit in
                WidgetHabit(
                    id: habit.id,
                    name: habit.name,
                    icon: habit.icon,
                    colorIndex: habit.colorIndex,
                    status: data.status(habit.id, day: key),
                    time: habit.reminder?.text,
                    progress: widgetProgress(habit, data: data, key: key),
                    countText: widgetCount(habit, data: data, key: key),
                    countsInTotal: habit.schedule.kind != .weekly,
                    goalMet: habit.schedule.kind == .weekly && data.weeklyGoalMet(habit, before: date, calendar: calendar)
                )
            }
            .sorted { lhs, rhs in
                // Неотмеченные выше, внутри - тот же порядок, что в приложении.
                let l = lhs.status == nil ? 0 : 1
                let r = rhs.status == nil ? 0 : 1
                if l != r { return l < r }
                return (position[lhs.id] ?? 0) < (position[rhs.id] ?? 0)
            }
        return HabitsEntry(date: date, dayKey: key, items: items)
    }

    private static func widgetProgress(_ habit: Habit, data: AppData, key: String) -> Double {
        let target = habit.dailyTarget(isPro: data.isPro)
        guard target > 1 else { return 0 }
        return Double(data.count(of: habit, day: key)) / Double(target)
    }

    private static func widgetCount(_ habit: Habit, data: AppData, key: String) -> String? {
        let target = habit.dailyTarget(isPro: data.isPro)
        let count = data.count(of: habit, day: key)
        guard target > 1, count > 0, count < target else { return nil }
        return "\(count)"
    }
}

// MARK: - Виджеты

@main
struct HabitsWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        ProgressWidget()
    }
}

struct TodayWidget: Widget {
    let kind = "TodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitsProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's habits")
        .description("Today's progress and quick check-off right from the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ProgressWidget: Widget {
    let kind = "ProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitsProvider()) { entry in
            LockScreenView(entry: entry)
                .containerBackground(Color.clear, for: .widget)
        }
        .configurationDisplayName("Habit progress")
        .description("How many habits are done today.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Главный экран

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HabitsEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallView(entry: entry)
        case .systemLarge:
            ListWidgetView(entry: entry, limit: 7, showsHeader: true)
        default:
            MediumView(entry: entry)
        }
    }
}

private struct RingSummary: View {
    let entry: HabitsEntry
    var size: CGFloat
    var lineWidth: CGFloat

    var body: some View {
        ZStack {
            ProgressRing(progress: entry.progress, lineWidth: lineWidth, color: .accentColor)
            if entry.total > 0 && entry.done == entry.total {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.3, weight: .heavy))
                    .foregroundStyle(Color.accentColor)
            } else {
                VStack(spacing: 0) {
                    Text("\(entry.done)")
                        .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    Text("of \(entry.total)")
                        .font(.system(size: size * 0.13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

private struct SmallView: View {
    let entry: HabitsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                RingSummary(entry: entry, size: 62, lineWidth: 8)
                Spacer(minLength: 0)
                if let next = entry.pending.first {
                    Button(intent: ToggleHabitIntent(habitID: next.id, day: entry.dayKey)) {
                        CheckMark(status: nil, color: Palette.color(next.colorIndex), size: 30)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
            if entry.items.isEmpty {
                Text("Free day today")
                    .font(.subheadline.weight(.semibold))
            } else if let next = entry.pending.first {
                Text("Next")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(next.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            } else {
                Text("All done")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

private struct MediumView: View {
    let entry: HabitsEntry

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                RingSummary(entry: entry, size: 70, lineWidth: 9)
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ListWidgetView(entry: entry, limit: 3, showsHeader: false)
        }
    }
}

private struct ListWidgetView: View {
    let entry: HabitsEntry
    let limit: Int
    let showsHeader: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                HStack(spacing: 12) {
                    RingSummary(entry: entry, size: 48, lineWidth: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today")
                            .font(.headline)
                        Text(entry.total == 0 ? String(localized: "No habits") : String(localized: "\(entry.done) of \(entry.total) done"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 4)
            }
            if entry.items.isEmpty {
                Spacer(minLength: 0)
                Text("No habits today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.items.prefix(limit)) { item in
                    WidgetHabitRow(item: item, dayKey: entry.dayKey)
                }
                if entry.items.count > limit {
                    Text("And \(entry.items.count - limit) more")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WidgetHabitRow: View {
    let item: WidgetHabit
    let dayKey: String

    var body: some View {
        let color = Palette.color(item.colorIndex)
        HStack(spacing: 10) {
            HabitIconView(icon: item.icon, color: color, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .strikethrough(item.status == .done, color: .secondary)
                    .foregroundStyle(item.status == nil ? Color.primary : Color.secondary)
                if let time = item.time {
                    Text(time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Button(intent: ToggleHabitIntent(habitID: item.id, day: dayKey)) {
                CheckMark(status: item.status, color: color, size: 26, progress: item.progress, countText: item.countText)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Экран блокировки

struct LockScreenView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HabitsEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.progress) {
                Image(systemName: "checkmark")
            } currentValueLabel: {
                Text("\(entry.done)/\(entry.total)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryInline:
            Label("\(entry.done) of \(entry.total) habits", systemImage: "checkmark.circle")
        default:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Habits \(entry.done)/\(entry.total)")
                        .font(.headline)
                }
                if let next = entry.pending.first {
                    Text(next.time.map { "\($0) \(next.name)" } ?? next.name)
                        .lineLimit(1)
                } else {
                    Text(entry.total == 0 ? String(localized: "Free day today") : String(localized: "All done"))
                }
                ProgressView(value: entry.progress)
            }
            .widgetAccentable()
        }
    }
}
