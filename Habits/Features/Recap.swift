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

    /// Первый и последний день итогов.
    struct Interval: Equatable {
        let start: Date
        let end: Date
    }

    /// Вариант карточки на «Сегодня»: какой период и за какие дни.
    struct BannerCandidate: Equatable {
        let period: Period
        let interval: Interval
    }

    /// Меньше недели в итогах показывать нечего: «год» из 1–2 дней в начале января.
    static let minimumDays = 7

    static func current(_ period: Period, in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> Recap {
        let range = interval(period, in: data, now: now, calendar: calendar)
        return make(period, from: range.start, to: range.end, in: data, now: now, calendar: calendar)
    }

    /// Дни, за которые считаются итоги периода.
    static func interval(_ period: Period, in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> Interval {
        switch period {
        case .week: lastWeekInterval(now: now, calendar: calendar)
        case .month: lastMonthInterval(now: now, calendar: calendar)
        case .year: yearInterval(in: data, now: now, calendar: calendar)
        }
    }

    /// Есть ли смысл предлагать итоги периода: в нём хотя бы неделя и были привычки.
    /// Считается без обхода дней, поэтому годится для `body`.
    static func isAvailable(_ period: Period, in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> Bool {
        let range = interval(period, in: data, now: now, calendar: calendar)
        let days = (calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 0) + 1
        return days >= minimumDays && hasHabits(in: range, data: data, calendar: calendar)
    }

    /// Были ли в эти дни привычки, которые отмечают (по датам начала и конца, без обхода дней).
    static func hasHabits(in range: Interval, data: AppData, calendar: Calendar = .app) -> Bool {
        data.trackedHabits.contains { habit in
            habit.firstDay(calendar: calendar) <= range.end && (habit.lastDay(calendar: calendar) ?? range.end) >= range.start
        }
    }

    static func lastWeekInterval(now: Date = Date(), calendar: Calendar = .app) -> Interval {
        let thisWeek = Stats.startOfWeek(now, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek
        return Interval(start: start, end: calendar.date(byAdding: .day, value: 6, to: start) ?? start)
    }

    static func lastMonthInterval(now: Date = Date(), calendar: Calendar = .app) -> Interval {
        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
        return Interval(start: start, end: calendar.date(byAdding: .day, value: -1, to: thisMonth) ?? start)
    }

    static func lastYearInterval(now: Date = Date(), calendar: Calendar = .app) -> Interval {
        let thisYear = calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .year, value: -1, to: thisYear) ?? thisYear
        return Interval(start: start, end: calendar.date(byAdding: .day, value: -1, to: thisYear) ?? start)
    }

    /// Итоги года. В декабре год уже почти прожит, и делятся обычно им, поэтому берём
    /// текущий год по вчерашний день. В остальные месяцы прошлый полный год, а если тогда
    /// привычек ещё не было (их завели в этом году), тоже текущий год по вчерашний день.
    static func yearInterval(in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> Interval {
        let today = calendar.startOfDay(for: now)
        let thisYear = calendar.dateInterval(of: .year, for: today)?.start ?? today
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let thisYearSoFar = Interval(start: thisYear, end: yesterday)
        guard yesterday >= thisYear else { return lastYearInterval(now: now, calendar: calendar) }
        if calendar.component(.month, from: today) == 12 { return thisYearSoFar }
        let lastYear = lastYearInterval(now: now, calendar: calendar)
        return hasHabits(in: lastYear, data: data, calendar: calendar) ? lastYear : thisYearSoFar
    }

    static func lastWeek(in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> Recap {
        current(.week, in: data, now: now, calendar: calendar)
    }

    static func lastMonth(in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> Recap {
        current(.month, in: data, now: now, calendar: calendar)
    }

    static func year(in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> Recap {
        current(.year, in: data, now: now, calendar: calendar)
    }

    // MARK: Карточка на «Сегодня»

    /// Какие итоги предложить на «Сегодня», по приоритету: в первые три дня января прошлый год,
    /// в первые три дня месяца прошлый месяц, в первые три дня недели прошлая неделя.
    /// Закрытые (ключ первого дня совпадает с `dismissed`) пропускаются. Данные не смотрим:
    /// первый кандидат, у которого есть данные, выбирает вызывающий.
    static func bannerCandidates(dismissed: [Period: String], now: Date = Date(), calendar: Calendar = .app) -> [BannerCandidate] {
        let today = calendar.startOfDay(for: now)
        let dayOfMonth = calendar.component(.day, from: today)
        let daysIntoWeek = calendar.dateComponents([.day], from: Stats.startOfWeek(today, calendar: calendar), to: today).day ?? 0
        var result: [BannerCandidate] = []
        if dayOfMonth <= 3, calendar.component(.month, from: today) == 1 {
            result.append(BannerCandidate(period: .year, interval: lastYearInterval(now: now, calendar: calendar)))
        }
        if dayOfMonth <= 3 {
            result.append(BannerCandidate(period: .month, interval: lastMonthInterval(now: now, calendar: calendar)))
        }
        if daysIntoWeek < 3 {
            result.append(BannerCandidate(period: .week, interval: lastWeekInterval(now: now, calendar: calendar)))
        }
        return result.filter { dismissed[$0.period] != DayKey.make($0.interval.start, calendar: calendar) }
    }

    /// Итоги для карточки на «Сегодня»: первый кандидат, за который есть отметки.
    static func banner(in data: AppData, dismissed: [Period: String], now: Date = Date(), calendar: Calendar = .app) -> Recap? {
        for candidate in bannerCandidates(dismissed: dismissed, now: now, calendar: calendar)
        where hasHabits(in: candidate.interval, data: data, calendar: calendar) {
            let recap = make(candidate.period, from: candidate.interval.start, to: candidate.interval.end, in: data, now: now, calendar: calendar)
            if recap.hasData { return recap }
        }
        return nil
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
        // Самая стабильная привычка ищется среди тех, что прожили хотя бы половину периода:
        // иначе привычка, заведённая за три дня до конца года, обошла бы годовую с 3 из 3.
        let halfway = dates.isEmpty ? start : dates[(dates.count - 1) / 2]

        var top: Top?
        var streakName: String?
        var streak = 0
        for habit in data.trackedHabits where habit.schedule.kind != .weekly {
            // Заморозки и починки за искры не прерывают серию, как и везде в приложении.
            let stats = Stats.habit(habit, in: data, now: period == .week ? now : afterEnd, calendar: calendar)
            var done = 0
            var total = 0
            var scheduled = 0
            var run = 0
            var best = 0
            for (date, key) in zip(dates, keys) where habit.isScheduled(on: date, calendar: calendar) {
                scheduled += 1
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

            // Порог от числа нужных дней самой привычки, а не длины периода: привычка
            // «по понедельникам» тоже может стать самой стабильной за месяц.
            guard total >= max(3, scheduled / 2), done > 0,
                  habit.firstDay(calendar: calendar) <= halfway else { continue }
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
