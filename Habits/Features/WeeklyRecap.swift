import Foundation

/// Итоги прошлой недели: процент, идеальные дни, лучшая серия и самая стабильная привычка.
struct WeeklyRecap: Equatable {
    struct Top: Equatable {
        let name: String
        let done: Int
        let total: Int
    }

    /// Понедельник (или первый день недели по календарю) и последний день недели.
    let start: Date
    let end: Date
    let days: [DayProgress]
    let streakName: String?
    let streak: Int
    let top: Top?

    var done: Int { days.map(\.done).reduce(0, +) }
    var total: Int { days.map(\.total).reduce(0, +) }
    var rate: Double { total == 0 ? 0 : Double(done) / Double(total) }
    var percent: Int { Int((rate * 100).rounded()) }
    var perfectDays: Int { days.filter { $0.total > 0 && $0.done == $0.total }.count }
    var hasData: Bool { total > 0 }
    /// Ключ недели, чтобы не показывать одну и ту же карточку на «Сегодня» снова.
    var key: String { DayKey.make(start) }

    /// Прошлая полная неделя.
    static func lastWeek(in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> WeeklyRecap {
        let thisWeek = Stats.startOfWeek(now, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek
        return make(from: start, in: data, calendar: calendar)
    }

    static func make(from start: Date, in data: AppData, calendar: Calendar = .app) -> WeeklyRecap {
        let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let days = dates.map { Stats.day($0, in: data, calendar: calendar) }

        // Самая стабильная привычка недели: больше всего выполнено при хотя бы 3 нужных днях.
        var top: Top?
        for habit in data.trackedHabits where habit.schedule.kind != .weekly {
            var done = 0
            var total = 0
            for date in dates where habit.isScheduled(on: date, calendar: calendar) {
                switch data.status(habit.id, day: DayKey.make(date, calendar: calendar)) {
                case .some(.done):
                    done += 1
                    total += 1
                case .some(.skipped):
                    break
                case .none:
                    total += 1
                }
            }
            guard total >= 3, done > 0 else { continue }
            let rate = Double(done) / Double(total)
            if let best = top {
                let bestRate = Double(best.done) / Double(best.total)
                if rate > bestRate || (rate == bestRate && done > best.done) {
                    top = Top(name: habit.name, done: done, total: total)
                }
            } else {
                top = Top(name: habit.name, done: done, total: total)
            }
        }

        // Лучшая текущая серия в днях.
        var streakName: String?
        var streak = 0
        for habit in data.trackedHabits {
            let stats = Stats.habit(habit, in: data)
            if !stats.isWeekly, stats.currentStreak > streak {
                streak = stats.currentStreak
                streakName = habit.name
            }
        }

        return WeeklyRecap(
            start: start,
            end: dates.last ?? start,
            days: days,
            streakName: streakName,
            streak: streak,
            top: top
        )
    }
}
