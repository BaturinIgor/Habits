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

/// Почему виджет не может показать данные.
enum WidgetProblem {
    /// Нет общего контейнера с приложением (группа приложений не выдана при установке).
    case noAccess
    /// Файл пока нельзя прочитать (телефон не разблокирован после перезагрузки).
    case locked
}

struct HabitsEntry: TimelineEntry {
    let date: Date
    let dayKey: String
    let items: [WidgetHabit]
    var problem: WidgetProblem? = nil

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
            let (data, problem) = Self.load()
            var entry = Self.entry(for: Date(), data: data)
            entry.problem = problem
            completion(entry)
        }
    }

    /// Читает данные и сообщает, если прочитать их нельзя.
    static func load() -> (AppData, WidgetProblem?) {
        guard AppGroup.resolvedIdentifier != nil else { return (AppData(), .noAccess) }
        guard let data = DataFile.loadIfAvailable() else { return (AppData(), .locked) }
        WidgetHeartbeat.write(habitCount: data.activeHabits.count)
        return (data, nil)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitsEntry>) -> Void) {
        let (data, problem) = Self.load()
        if let problem {
            // Попробуем снова через 15 минут: возможно, телефон разблокируют.
            var entry = Self.entry(for: Date(), data: data)
            entry.problem = problem
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
            return
        }
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
        PetWidget()
        ProgressWidget()
    }
}

struct TodayWidget: Widget {
    let kind = "TodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitsProvider()) { entry in
            Group {
                if let problem = entry.problem {
                    WidgetProblemView(problem: problem)
                } else {
                    TodayWidgetView(entry: entry)
                }
            }
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

struct WidgetProblemView: View {
    let problem: WidgetProblem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: problem == .noAccess ? "exclamationmark.triangle.fill" : "lock.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            Text(problem == .noAccess ? "No access to app data" : "Unlock your iPhone")
                .font(.subheadline.weight(.semibold))
            Text(problem == .noAccess ? "Reinstall the app and keep its extensions. Details are in Settings, Widget." : "The widget will update after unlocking.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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

// MARK: - Питомец

struct PetEntry: TimelineEntry {
    let date: Date
    var pet: PetState?
    var stage: PetStage = .egg
    var mood: PetMood = .calm
    var xp = 0
    var balance = 0
    var feedsToday = 0
    var done = 0
    var total = 0
    var problem: WidgetProblem?

    static var sample: PetEntry {
        PetEntry(date: Date(), pet: PetState(species: "cat", name: String(localized: "Buddy"), adoptedAt: Date()),
                 stage: .young, mood: .happy, xp: 70, balance: 42, feedsToday: 1, done: 2, total: 4)
    }

    var canFeed: Bool { pet != nil && feedsToday < Sparks.feedsPerDay && balance >= Sparks.feedPrice }
}

struct PetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PetEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (PetEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
        } else {
            completion(Self.entry(at: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PetEntry>) -> Void) {
        let now = Date()
        let first = Self.entry(at: now)
        if first.problem != nil {
            completion(Timeline(entries: [first], policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }
        // Настроение меняется со временем (сон ночью), поэтому записи на каждый час.
        var entries = [first]
        for hour in 1...12 {
            entries.append(Self.entry(at: now.addingTimeInterval(Double(hour) * 3600)))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static func entry(at date: Date) -> PetEntry {
        let (data, problem) = HabitsProvider.load()
        var entry = PetEntry(date: date, problem: problem)
        guard problem == nil else { return entry }
        let progress = Stats.day(date, in: data)
        entry.done = progress.done
        entry.total = progress.total
        entry.balance = Sparks.snapshotBalance(data)
        guard let pet = data.wallet.pet else { return entry }
        entry.pet = pet
        entry.xp = Pets.xp(pet, data: data)
        entry.stage = PetStage.stage(xp: entry.xp)
        entry.mood = Pets.mood(pet, data: data, now: date)
        entry.feedsToday = pet.feeds[DayKey.make(date), default: 0]
        return entry
    }
}

struct PetWidget: Widget {
    let kind = "PetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PetProvider()) { entry in
            Group {
                if let problem = entry.problem {
                    WidgetProblemView(problem: problem)
                } else {
                    PetWidgetView(entry: entry)
                }
            }
            .containerBackground(for: .widget) {
                LinearGradient(colors: [Color.orange.opacity(0.18), Color.pink.opacity(0.12)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .configurationDisplayName("Pet")
        .description("Your pet's mood and feeding right from the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PetEntry

    var body: some View {
        if let pet = entry.pet {
            if family == .systemSmall {
                VStack(spacing: 4) {
                    HStack {
                        Text(pet.name).font(.caption.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                        SparkBadge(amount: entry.balance, font: .caption2.weight(.bold))
                    }
                    PetAvatar(pet: pet, stage: entry.stage, mood: entry.mood, size: 78)
                    feedButton(compact: true)
                }
            } else {
                HStack(spacing: 14) {
                    PetAvatar(pet: pet, stage: entry.stage, mood: entry.mood, size: 110)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(pet.name).font(.headline).lineLimit(1)
                            Spacer(minLength: 0)
                            SparkBadge(amount: entry.balance, font: .caption.weight(.bold))
                        }
                        Text("\(entry.stage.title) · \(entry.mood.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let next = entry.stage.next {
                            ProgressView(value: Double(entry.xp - entry.stage.threshold),
                                         total: Double(next.threshold - entry.stage.threshold))
                                .tint(.orange)
                        }
                        if entry.total > 0 {
                            Text("\(entry.done) of \(entry.total) done")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        feedButton(compact: false)
                    }
                }
            }
        } else {
            VStack(spacing: 6) {
                Text(verbatim: "🥚").font(.system(size: 44))
                Text("Get a pet").font(.subheadline.weight(.semibold))
                Text("Open the app to adopt one.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func feedButton(compact: Bool) -> some View {
        if entry.feedsToday >= Sparks.feedsPerDay {
            Text("Full for today")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
        } else {
            Button(intent: FeedPetIntent()) {
                HStack(spacing: 4) {
                    Text(verbatim: "🍓")
                    if !compact { Text("Feed") }
                    SparkBadge(amount: Sparks.feedPrice, font: .caption2.weight(.bold))
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.orange.opacity(entry.canFeed ? 0.25 : 0.1)))
            }
            .buttonStyle(.plain)
            .disabled(!entry.canFeed)
        }
    }
}
