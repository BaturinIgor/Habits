import SwiftUI

/// Оценка настроения: от 1 (плохо) до 5 (отлично).
enum MoodLevel: Int, CaseIterable, Identifiable {
    case awful = 1, bad, okay, good, great

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .awful: "😣"
        case .bad: "🙁"
        case .okay: "😐"
        case .good: "🙂"
        case .great: "😄"
        }
    }

    var title: String {
        switch self {
        case .awful: String(localized: "Awful")
        case .bad: String(localized: "Bad")
        case .okay: String(localized: "Okay")
        case .good: String(localized: "Good")
        case .great: String(localized: "Great")
        }
    }

    var color: Color {
        switch self {
        case .awful: Color(red: 0.55, green: 0.45, blue: 0.85)
        case .bad: Color(red: 0.4, green: 0.6, blue: 0.95)
        case .okay: Color(red: 0.55, green: 0.75, blue: 0.75)
        case .good: Color(red: 0.4, green: 0.8, blue: 0.45)
        case .great: Color(red: 1.0, green: 0.7, blue: 0.2)
        }
    }

    init(clamping value: Int) {
        self = MoodLevel(rawValue: min(5, max(1, value))) ?? .okay
    }
}

/// Записи дневника и связь настроения с привычками.
enum MoodJournal {
    /// Сколько последних дней истории видно без Pro.
    static let freeDays = 7

    struct Item: Identifiable, Hashable {
        let day: String
        let date: Date
        let entry: MoodEntry
        var id: String { day }
        var level: MoodLevel { MoodLevel(clamping: entry.level) }
    }

    /// Привычка и насколько настроение выше в дни, когда она выполнена.
    struct Impact: Identifiable, Hashable {
        let habit: Habit
        /// Разница средних оценок: в дни с выполненной привычкой минус в остальные дни, когда она была по плану.
        let delta: Double
        let doneDays: Int
        var id: UUID { habit.id }
    }

    /// Все записи, от новых к старым.
    static func items(in data: AppData) -> [Item] {
        data.moods.compactMap { key, entry in
            DayKey.date(key).map { Item(day: key, date: $0, entry: entry) }
        }
        .sorted { $0.date > $1.date }
    }

    /// Запись видна без Pro, если она не старше `freeDays` дней.
    static func isFree(_ date: Date, now: Date = Date(), calendar: Calendar = .app) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let edge = calendar.date(byAdding: .day, value: -(freeDays - 1), to: today) else { return true }
        return calendar.startOfDay(for: date) >= edge
    }

    /// Средняя оценка за последние `days` дней (только дни с записью).
    static func average(in data: AppData, days: Int, now: Date = Date(), calendar: Calendar = .app) -> Double? {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return nil }
        let levels = data.moods.compactMap { key, entry -> Int? in
            guard let date = DayKey.date(key, calendar: calendar), date >= start, date <= today else { return nil }
            return entry.level
        }
        guard !levels.isEmpty else { return nil }
        return Double(levels.reduce(0, +)) / Double(levels.count)
    }

    /// Инсайты настроения (KAN-137): сколько дней нужно с каждой стороны - с выполненной привычкой и без неё.
    static let insightMinDays = 7
    /// Разница средних, начиная с которой привычку показываем.
    static let insightMinDelta = 0.3
    /// Сколько последних дней истории учитывается.
    static let insightWindowDays = 90

    /// Что показать в карточке инсайтов.
    enum Insights: Equatable {
        /// Привычки с самым большим плюсом, не больше трёх.
        case ready([Impact])
        /// Данных мало: примерно столько ещё дней отмечать настроение.
        case needMoreDays(Int)
        /// Данных хватает, но ни одна привычка не выделяется.
        case noLift
    }

    /// Сравнивает среднее настроение в дни, когда привычка выполнена, и в дни по плану, когда нет.
    /// Учитываются только привычки, у которых не меньше `minDays` таких дней с каждой стороны,
    /// иначе вывод был бы случайным. Сегодняшний день не учитывается: привычку ещё могут отметить.
    /// Это связь, а не причина: тексты в карточке говорят «в дни с привычкой настроение выше».
    static func insights(in data: AppData, now: Date = Date(), calendar: Calendar = .app,
                         minDays: Int = insightMinDays, limit: Int = 3) -> Insights {
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -insightWindowDays, to: today) ?? today
        let entries = data.moods.compactMap { key, entry -> (String, Date, Int)? in
            guard let date = DayKey.date(key, calendar: calendar), date >= windowStart, date < today else { return nil }
            return (key, date, entry.level)
        }
        var lifts: [Impact] = []
        var anyQualified = false
        // Меньше всего дней, которых не хватает какой-нибудь привычке.
        var fewestMissing: Int?
        for habit in data.activeHabits where habit.quit == nil {
            var done: [Int] = []
            var missed: [Int] = []
            for (key, date, level) in entries where habit.isScheduled(on: date, calendar: calendar) {
                if data.status(habit.id, day: key) == .done {
                    done.append(level)
                } else {
                    missed.append(level)
                }
            }
            let missing = max(0, minDays - done.count) + max(0, minDays - missed.count)
            guard missing == 0 else {
                fewestMissing = min(fewestMissing ?? missing, missing)
                continue
            }
            anyQualified = true
            let delta = mean(done) - mean(missed)
            guard delta >= insightMinDelta else { continue }
            lifts.append(Impact(habit: habit, delta: delta, doneDays: done.count))
        }
        if !lifts.isEmpty {
            // Сравниваем с точностью до сотых: на экране одна цифра после запятой, а почти равные
            // привычки пусть идут в порядке списка, а не по шуму округления.
            func rank(_ impact: Impact) -> Int { Int((impact.delta * 100).rounded()) }
            let sorted = lifts.sorted { rank($0) != rank($1) ? rank($0) > rank($1) : Habit.manualOrder($0.habit, $1.habit) }
            return .ready(Array(sorted.prefix(limit)))
        }
        // Подходящих привычек нет совсем: подсказывать «сколько ещё дней» не о чем.
        guard !anyQualified, let fewestMissing else { return .noLift }
        return .needMoreDays(max(1, fewestMissing))
    }

    private static func mean(_ values: [Int]) -> Double {
        Double(values.reduce(0, +)) / Double(max(1, values.count))
    }
}
