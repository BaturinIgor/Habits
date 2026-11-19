import XCTest
@testable import Habits

/// Скорость на «тяжёлом» пользователе: 20 привычек и 3 года отметок.
/// Каждое касание кружка сохраняет файл и пересчитывает искры, ачивки и серии,
/// поэтому эти расчёты должны укладываться в доли секунды даже на медленном симуляторе CI.
final class PerformanceTests: XCTestCase {
    private static let heavy: AppData = {
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -1095, to: today)!
        var data = AppData()
        data.settings.proUnlocked = true
        for n in 0..<20 {
            var habit = Habit(name: "Habit \(n)", schedule: HabitSchedule(startDate: start), createdAt: start, sortOrder: n)
            if n % 5 == 1 { habit.schedule = HabitSchedule(weekdays: [2, 3, 4, 5, 6], startDate: start) }
            if n % 5 == 2 { habit.schedule = HabitSchedule(kind: .weekly, startDate: start, timesPerWeek: 3) }
            if n % 5 == 3 { habit.target = 8 }
            data.habits.append(habit)
            for offset in 0..<1095 where (offset + n) % 7 != 0 {
                let day = calendar.date(byAdding: .day, value: offset, to: start)!
                data.setStatus(.done, habitID: habit.id, day: DayKey.make(day))
            }
        }
        return data
    }()

    /// Замер в секундах (лучшее из нескольких повторов, чтобы не ловить шум CI).
    private func time(_ label: String, limit: TimeInterval, repeats: Int = 3, _ work: () -> Void) {
        var best = TimeInterval.infinity
        for _ in 0..<repeats {
            let start = CFAbsoluteTimeGetCurrent()
            work()
            best = min(best, CFAbsoluteTimeGetCurrent() - start)
        }
        print(String(format: "PERF %@: %.0f ms (limit %.0f ms)", label, best * 1000, limit * 1000))
        XCTAssertLessThan(best, limit, "\(label) is too slow: \(Int(best * 1000)) ms")
    }

    func testCheckInPipelineIsFast() {
        let data = Self.heavy
        XCTAssertGreaterThan(data.checkIns.count, 18_000)

        time("save file (encode)", limit: 0.4) {
            _ = try? JSONEncoder().encode(data)
        }
        let raw = try! JSONEncoder().encode(data)
        time("load file (decode)", limit: 0.6) {
            _ = try? JSONDecoder().decode(AppData.self, from: raw)
        }
        time("achievement facts", limit: 0.6) {
            _ = AchievementFacts(data: data)
        }
        let facts = AchievementFacts(data: data)
        time("sparks report", limit: 0.6) {
            let unlocked = Achievements.all.filter { $0.isUnlocked(facts) }.count
            _ = Sparks.report(data, facts: facts, unlockedAchievements: unlocked)
        }
        time("streaks of all habits", limit: 0.6) {
            for habit in data.habits { _ = Stats.habit(habit, in: data) }
        }
    }

    func testStatisticsScreenMathIsFast() {
        let data = Self.heavy
        time("today + last 7 days + 30-day rate", limit: 0.3) {
            _ = Stats.day(Date(), in: data)
            _ = Stats.lastDays(7, in: data)
            _ = Stats.overallRate(days: 30, in: data)
        }
        time("16-week heatmap", limit: 0.3) {
            _ = Stats.lastDays(16 * 7, in: data)
        }
        time("weekly rates of all habits", limit: 0.6) {
            for habit in data.habits { _ = Stats.weeklyRates(habit, in: data, weeks: 12) }
        }
        time("week in review", limit: 0.6) {
            _ = Recap.lastWeek(in: data)
        }
        time("month in review", limit: 0.6) {
            _ = Recap.lastMonth(in: data)
        }
        time("year in review", limit: 0.8) {
            _ = Recap.year(in: data)
        }
    }

    /// Статистика не должна тормозить: daily_state считается в фоне при запуске (но держит ядро и батарею),
    /// а параметры собираются на главном потоке на каждое нажатие (событие gesture).
    func testAnalyticsIsCheap() {
        var data = Self.heavy
        // С питомцем: снимок считает его стадию по опыту за все отметки.
        data.wallet.pet = PetState(species: Pets.all[0].id, name: "Buddy", adoptedAt: Date().addingTimeInterval(-86400 * 365))
        time("daily_state snapshot", limit: 0.3) {
            _ = AnalyticsSnapshot.make(data)
        }
        time("1000 gesture payloads", limit: 0.1) {
            for _ in 0..<1000 {
                _ = Analytics.firebaseParameters(["screen": "Today", "kind": "tap"])
            }
        }
    }
}
