import Foundation

/// Итоги недели, месяца или года: процент, идеальные дни, лучшая серия и самая стабильная привычка.
struct Recap: Equatable, Identifiable {
    enum Period: String, Identifiable, CaseIterable {
        case week, month, year
        var id: String { rawValue }

        var campaign: ShareCampaign {
            switch self {
            case .week: .weekly
            case .month: .month
            case .year: .year
            }
        }
    }

    struct Top: Equatable {
        let name: String
        let done: Int
        let total: Int
    }

    let period: Period
    /// Первый и последний день итогов.
    let start: Date
    let end: Date
    let days: [DayProgress]
    /// Столбики графика: дни недели или месяца, у года 12 месяцев (дата столбика = 1-е число).
    let bars: [DayProgress]
    let streakName: String?
    /// У недели текущая серия, у месяца и года самая длинная серия внутри периода.
    let streak: Int
    let top: Top?
    /// false, если год ещё идёт и итоги «с начала года по вчера».
    let isComplete: Bool

    var done: Int { days.map(\.done).reduce(0, +) }
    var total: Int { days.map(\.total).reduce(0, +) }
    var rate: Double { total == 0 ? 0 : Double(done) / Double(total) }
    var percent: Int { Int((rate * 100).rounded()) }
    var perfectDays: Int { days.filter { $0.total > 0 && $0.done == $0.total }.count }
    var hasData: Bool { total > 0 }
    /// Ключ периода, чтобы не показывать одну и ту же карточку на «Сегодня» снова.
    var key: String { DayKey.make(start) }
    var id: String { period.rawValue + "-" + key }

    // MARK: Периоды

    static func current(_ period: Period, in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> Recap {
        switch period {
        case .week: lastWeek(in: data, now: now, calendar: calendar)
        case .month: lastMonth(in: data, now: now, calendar: calendar)
        case .year: year(in: data, now: now, calendar: calendar)
        }
    }

    /// Первый день прошлой недели.
    static func lastWeekStart(now: Date = Date(), calendar: Calendar = .app) -> Date {
        let thisWeek = Stats.startOfWeek(now, calendar: calendar)
        return calendar.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek
    }

    /// Прошлая полная неделя.
    static func lastWeek(in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> Recap {
        let start = lastWeekStart(now: now, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return make(.week, from: start, to: end, in: data, now: now, calendar: calendar)
    }

    /// Первое число прошлого месяца.
    static func lastMonthStart(now: Date = Date(), calendar: Calendar = .app) -> Date {
        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        return calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
    }

    /// Прошлый полный месяц.
    static func lastMonth(in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> Recap {
        let start = lastMonthStart(now: now, calendar: calendar)
        let next = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        let end = calendar.date(byAdding: .day, value: -1, to: next) ?? start
        return make(.month, from: start, to: end, in: data, now: now, calendar: calendar)
    }

    /// Итоги года. В декабре год уже почти прожит, и делятся обычно им, поэтому показываем
    /// текущий год по вчерашний день. В остальные месяцы прошлый полный год, а если за него
    /// нет данных (привычки завели в этом году), тоже текущий год по вчерашний день.
    static func year(in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> Recap {
        let today = calendar.startOfDay(for: now)
        let thisYear = calendar.dateInterval(of: .year, for: today)?.start ?? today
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let canShowThisYear = yesterday >= thisYear
        if canShowThisYear, calendar.component(.month, from: today) == 12 {
            return make(.year, from: thisYear, to: yesterday, in: data, now: now, calendar: calendar)
        }
        let lastYearStart = calendar.date(byAdding: .year, value: -1, to: thisYear) ?? thisYear
        let lastYearEnd = calendar.date(byAdding: .day, value: -1, to: thisYear) ?? thisYear
        let lastYear = make(.year, from: lastYearStart, to: lastYearEnd, in: data, now: now, calendar: calendar)
        if canShowThisYear, !lastYear.hasData {
            return make(.year, from: thisYear, to: yesterday, in: data, now: now, calendar: calendar)
        }
        return lastYear
    }

    // MARK: Подсчёт

    static func make(_ period: Period, from start: Date, to end: Date, in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> Recap {
        let start = calendar.startOfDay(for: start)
        let end = calendar.startOfDay(for: end)
        var dates: [Date] = []
        var date = start
        while date <= end {
            dates.append(date)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        let days = dates.map { Stats.day($0, in: data, calendar: calendar) }
        let keys = dates.map { DayKey.make($0, calendar: calendar) }
        // Для серии внутри месяца или года: день после периода, чтобы его последний день считался прошедшим.
        let afterEnd = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        // Самая стабильная привычка: больше всего выполнено при достаточном числе нужных дней.
        let minTotal = max(3, min(dates.count / 4, 30))

        var top: Top?
        var streakName: String?
        var streak = 0
        for habit in data.trackedHabits where habit.schedule.kind != .weekly {
            // Заморозки и починки за искры не прерывают серию, как и везде в приложении.
            let stats = Stats.habit(habit, in: data, now: period == .week ? now : afterEnd, calendar: calendar)
            var done = 0
            var total = 0
            var run = 0
            var best = 0
            for (date, key) in zip(dates, keys) where habit.isScheduled(on: date, calendar: calendar) {
                switch data.status(habit.id, day: key) {
                case .some(.done):
                    done += 1
                    total += 1
                    run += 1
                    best = max(best, run)
                case .some(.skipped):
                    break
                case .none:
                    total += 1
                    if !stats.frozenDays.contains(key) && !stats.repairedDays.contains(key) { run = 0 }
                }
            }

            let habitStreak = period == .week ? stats.currentStreak : best
            if habitStreak > streak {
                streak = habitStreak
                streakName = habit.name
            }

            guard total >= minTotal, done > 0 else { continue }
            let rate = Double(done) / Double(total)
            if let current = top {
                let bestRate = Double(current.done) / Double(current.total)
                if rate > bestRate || (rate == bestRate && done > current.done) {
                    top = Top(name: habit.name, done: done, total: total)
                }
            } else {
                top = Top(name: habit.name, done: done, total: total)
            }
        }

        let isComplete: Bool
        let bars: [DayProgress]
        if period == .year {
            let yearStart = calendar.dateInterval(of: .year, for: start)?.start ?? start
            let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart).flatMap { calendar.date(byAdding: .day, value: -1, to: $0) } ?? end
            isComplete = end >= yearEnd
            var byMonth: [Int: (done: Int, total: Int)] = [:]
            for day in days {
                let month = calendar.component(.month, from: day.date)
                byMonth[month, default: (0, 0)].done += day.done
                byMonth[month, default: (0, 0)].total += day.total
            }
            bars = (0..<12).compactMap { offset in
                guard let monthStart = calendar.date(byAdding: .month, value: offset, to: yearStart) else { return nil }
                let sum = byMonth[calendar.component(.month, from: monthStart)] ?? (0, 0)
                return DayProgress(date: monthStart, done: sum.done, total: sum.total)
            }
        } else {
            isComplete = true
            bars = days
        }

        return Recap(
            period: period,
            start: start,
            end: dates.last ?? start,
            days: days,
            bars: bars,
            streakName: streakName,
            streak: streak,
            top: top,
            isComplete: isComplete
        )
    }
}
