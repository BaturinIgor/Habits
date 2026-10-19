import Foundation

extension Sparks {
    static func report(_ data: AppData, facts: AchievementFacts, unlockedAchievements: Int, calendar: Calendar = .app) -> SparkReport {
        var r = SparkReport()
        let perDay = checksPerDay(data, calendar: calendar)
        r.checks = perDay.values.reduce(0, +)
        for day in perDay.keys {
            guard let date = DayKey.date(day, calendar: calendar) else { continue }
            let p = Stats.day(date, in: data, calendar: calendar)
            if p.total > 0 && p.done == p.total { r.perfectDays += perfectDayBonus }
        }
        r.streaks = facts.streakWeeks * weekStreakBonus + facts.streakMonths * monthStreakBonus
        r.comebacks = facts.comebacks * comebackBonus
        r.achievements = unlockedAchievements * achievementBonus
        r.gifts = data.wallet.proMonths.count * proMonthlyGift
        return r
    }

}
