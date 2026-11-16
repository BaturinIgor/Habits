import XCTest
@testable import Habits

/// Проверки логики без интерфейса: серии, итоги недели, «Бросаю», таймер, формат данных.
final class LogicTests: XCTestCase {
    private let calendar = Calendar.app
    private var today: Date { calendar.startOfDay(for: Date()) }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    private func dailyHabit(startOffset: Int = -30) -> Habit {
        Habit(name: "Test", schedule: HabitSchedule(startDate: day(startOffset)), createdAt: day(startOffset))
    }

    // MARK: Серии

    func testStreakCountsConsecutiveDoneDays() {
        var data = AppData()
        let habit = dailyHabit(startOffset: -5)
        data.habits = [habit]
        for offset in -5 ... 0 {
            data.setStatus(.done, habitID: habit.id, day: DayKey.make(day(offset)))
        }
        let stats = Stats.habit(habit, in: data)
        XCTAssertEqual(stats.currentStreak, 6)
        XCTAssertEqual(stats.bestStreak, 6)
        XCTAssertEqual(stats.totalDone, 6)
    }

    func testRepairedDayKeepsStreak() {
        var data = AppData()
        let habit = dailyHabit(startOffset: -6)
        data.habits = [habit]
        for offset in -6 ... -1 where offset != -3 {
            data.setStatus(.done, habitID: habit.id, day: DayKey.make(day(offset)))
        }
        // Заморозки в месяце могли бы спасти серию сами, поэтому сравниваем с починкой и без.
        var repaired = data
        repaired.wallet.repairs.append(AppData.key(habit.id, DayKey.make(day(-3))))
        let fixed = Stats.habit(habit, in: repaired)
        XCTAssertTrue(fixed.repairedDays.contains(DayKey.make(day(-3))))
        XCTAssertGreaterThanOrEqual(fixed.currentStreak, Stats.habit(habit, in: data).currentStreak)
        XCTAssertEqual(fixed.currentStreak, 5)
    }

    // MARK: Итоги недели

    func testWeeklyRecapCountsLastFullWeek() {
        var data = AppData()
        let habit = dailyHabit(startOffset: -40)
        data.habits = [habit]
        let thisWeek = Stats.startOfWeek(Date())
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: thisWeek)!
        // 5 из 7 дней прошлой недели.
        for offset in 0..<5 {
            let date = calendar.date(byAdding: .day, value: offset, to: lastWeek)!
            data.setStatus(.done, habitID: habit.id, day: DayKey.make(date))
        }
        let recap = WeeklyRecap.lastWeek(in: data)
        XCTAssertEqual(calendar.startOfDay(for: recap.start), lastWeek)
        XCTAssertEqual(recap.days.count, 7)
        XCTAssertEqual(recap.done, 5)
        XCTAssertEqual(recap.total, 7)
        XCTAssertEqual(recap.perfectDays, 5)
        XCTAssertEqual(recap.percent, 71)
        XCTAssertEqual(recap.top?.name, "Test")
        XCTAssertTrue(recap.hasData)
    }

    func testWeeklyRecapIsEmptyWithoutHabits() {
        let recap = WeeklyRecap.lastWeek(in: AppData())
        XCTAssertFalse(recap.hasData)
        XCTAssertEqual(recap.percent, 0)
        XCTAssertNil(recap.top)
    }

    // MARK: Бросаю

    func testQuitRelapseKeepsRecord() {
        var quit = QuitInfo(startedAt: day(-20), dailyCost: 100)
        XCTAssertEqual(quit.days(), 20)
        quit.relapse(at: day(-5))
        XCTAssertEqual(quit.days(), 5)
        XCTAssertEqual(quit.best(), 15)
        XCTAssertEqual(quit.relapses.count, 1)
        XCTAssertEqual(quit.totalDays(), 19)
        XCTAssertEqual(quit.saved(), 1900)
    }

    func testQuitNextMilestone() {
        let quit = QuitInfo(startedAt: day(-10))
        let next = quit.nextMilestone()
        XCTAssertEqual(next.days, 14)
        XCTAssertGreaterThan(next.progress, 0)
        XCTAssertLessThan(next.progress, 1)
    }

    func testQuitHabitIsNeverScheduled() {
        var habit = dailyHabit()
        habit.quit = QuitInfo(startedAt: day(-3))
        XCTAssertFalse(habit.isScheduled(on: today))
        var data = AppData()
        data.habits = [habit]
        XCTAssertTrue(data.trackedHabits.isEmpty)
    }

    // MARK: Таймер и Health

    func testTimerClockFormat() {
        XCTAssertEqual(HabitTimerView.clock(600), "10:00")
        XCTAssertEqual(HabitTimerView.clock(65), "1:05")
        XCTAssertEqual(HabitTimerView.clock(5400), "1:30:00")
    }

    func testHealthGoalsAreInsideRange() {
        for metric in HealthLink.Metric.allCases {
            XCTAssertTrue(metric.range.contains(metric.defaultGoal), "\(metric)")
            XCTAssertGreaterThan(metric.step, 0, "\(metric)")
            XCTAssertFalse(metric.format(metric.defaultGoal).isEmpty)
        }
    }

    // MARK: Формат данных

    func testHabitRoundTripKeepsNewFields() throws {
        var habit = dailyHabit()
        habit.timerMinutes = 15
        habit.health = HealthLink(metric: .water, goal: 2)
        habit.quit = QuitInfo(startedAt: day(-2), dailyCost: 50)
        let decoded = try JSONDecoder().decode(Habit.self, from: JSONEncoder().encode(habit))
        XCTAssertEqual(decoded.timerMinutes, 15)
        XCTAssertEqual(decoded.health, habit.health)
        XCTAssertEqual(decoded.quit?.dailyCost, 50)
    }

    func testOldDataWithoutNewFieldsStillLoads() throws {
        var habit = dailyHabit()
        habit.timerMinutes = 5
        habit.health = HealthLink(metric: .steps, goal: 8000)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(habit)) as! [String: Any]
        json.removeValue(forKey: "timerMinutes")
        json.removeValue(forKey: "health")
        json.removeValue(forKey: "quit")
        let raw = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Habit.self, from: raw)
        XCTAssertNil(decoded.timerMinutes)
        XCTAssertNil(decoded.health)
        XCTAssertNil(decoded.quit)
        XCTAssertEqual(decoded.name, "Test")
    }

    /// Регресс 1.3.1: дни недели кодируются всегда в одном порядке, иначе семейная синхронизация зацикливалась.
    func testWeekdaysEncodeInStableOrder() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let start = today
        let first = try encoder.encode(HabitSchedule(weekdays: [7, 1, 4, 2], startDate: start, onceDate: start))
        for _ in 0..<20 {
            let again = try encoder.encode(HabitSchedule(weekdays: [2, 4, 1, 7], startDate: start, onceDate: start))
            XCTAssertEqual(again, first)
        }
    }

    func testDemoDataIsConsistent() {
        let data = UITestSupport.demoData()
        XCTAssertEqual(data.habits.count, 7)
        XCTAssertEqual(Set(data.habits.map(\.id)).count, 7)
        XCTAssertTrue(data.settings.onboardingDone)
        XCTAssertEqual(data.habits.filter(\.isQuit).count, 1)
        XCTAssertNotNil(data.habits.first { $0.timerMinutes != nil })
    }
}
