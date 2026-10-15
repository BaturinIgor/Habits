import Foundation

struct HabitStats: Hashable {
    var currentStreak = 0
    var bestStreak = 0
    /// Доля выполненных дней среди прошедших запланированных (пропуски не считаются).
    var completionRate: Double = 0
    var totalDone = 0
    var countedDays = 0
}

struct DayProgress: Identifiable, Hashable {
    let date: Date
    let done: Int
    let total: Int
    var id: Date { date }
    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

struct WeekRate: Identifiable, Hashable {
    let weekStart: Date
    let rate: Double
    let hasData: Bool
    var id: Date { weekStart }
}

enum Stats {
    /// Сколько дней назад максимум просматривать историю.
    private static let maxLookback = 1100

    static func habit(_ habit: Habit, in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> HabitStats {
        var result = HabitStats()
        let today = calendar.startOfDay(for: now)
        var day = habit.firstDay(calendar: calendar)
        if let earliest = calendar.date(byAdding: .day, value: -maxLookback, to: today), day < earliest {
            day = earliest
        }
        var last = today
        if let end = habit.lastDay(calendar: calendar), end < last { last = end }

        var run = 0
        var counted = 0
        while day <= last {
            if habit.isScheduled(on: day, calendar: calendar) {
                let status = data.status(habit.id, day: DayKey.make(day, calendar: calendar))
                switch status {
                case .some(.done):
                    run += 1
                    result.totalDone += 1
                    counted += 1
                    result.bestStreak = max(result.bestStreak, run)
                case .some(.skipped):
                    break
                case .none:
                    if day < today {
                        run = 0
                        counted += 1
                    }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        result.currentStreak = run
        result.countedDays = counted
        result.completionRate = counted > 0 ? Double(result.totalDone) / Double(counted) : 0
        return result
    }

    /// Выполнено и всего на день (пропущенные в "всего" не входят).
    static func day(_ date: Date, in data: AppData, calendar: Calendar = .app) -> DayProgress {
        let key = DayKey.make(date, calendar: calendar)
        let habits = data.habits(on: date, calendar: calendar)
        var done = 0
        var total = 0
        for habit in habits {
            switch data.status(habit.id, day: key) {
            case .some(.done):
                done += 1
                total += 1
            case .some(.skipped):
                break
            case .none:
                total += 1
            }
        }
        return DayProgress(date: calendar.startOfDay(for: date), done: done, total: total)
    }

    static func lastDays(_ count: Int, in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> [DayProgress] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { day($0, in: data, calendar: calendar) }
        }
    }

    /// Процент выполнения за последние N дней по всем привычкам (сегодня считается, только если отмечено).
    static func overallRate(days: Int, in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> Double {
        let today = calendar.startOfDay(for: now)
        var done = 0
        var total = 0
        for offset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let p = day(date, in: data, calendar: calendar)
            if offset == 0 {
                done += p.done
                total += p.done
            } else {
                done += p.done
                total += p.total
            }
        }
        return total == 0 ? 0 : Double(done) / Double(total)
    }

    static func startOfWeek(_ date: Date, calendar: Calendar = .app) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Процент выполнения по неделям для одной привычки.
    static func weeklyRates(_ habit: Habit, in data: AppData, weeks: Int, now: Date = Date(), calendar: Calendar = .app) -> [WeekRate] {
        let today = calendar.startOfDay(for: now)
        let thisWeek = startOfWeek(today, calendar: calendar)
        var result: [WeekRate] = []
        for w in (0..<weeks).reversed() {
            guard let weekStart = calendar.date(byAdding: .day, value: -7 * w, to: thisWeek) else { continue }
            var done = 0
            var total = 0
            for d in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: d, to: weekStart), day <= today else { continue }
                guard habit.isScheduled(on: day, calendar: calendar) else { continue }
                switch data.status(habit.id, day: DayKey.make(day, calendar: calendar)) {
                case .some(.done):
                    done += 1
                    total += 1
                case .some(.skipped):
                    break
                case .none:
                    if day < today { total += 1 }
                }
            }
            result.append(WeekRate(
                weekStart: weekStart,
                rate: total == 0 ? 0 : Double(done) / Double(total),
                hasData: total > 0
            ))
        }
        return result
    }
}
