import XCTest
@testable import Habits

/// Инсайты настроения (KAN-137): какие привычки идут вместе с лучшим настроением.
final class MoodInsightsTests: XCTestCase {
    private let calendar = Calendar.app
    private var today: Date { calendar.startOfDay(for: Date()) }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    private func habit(_ name: String, order: Int = 0) -> Habit {
        Habit(name: name, schedule: HabitSchedule(startDate: day(-120)), createdAt: day(-120), sortOrder: order)
    }

    /// Привычка выполнена в дни, где `done(offset)` - true; настроение по `mood(offset)`.
    private func fill(_ data: inout AppData, days: ClosedRange<Int>, habit: Habit, done: (Int) -> Bool, mood: (Int) -> Int) {
        for offset in days {
            let key = DayKey.make(day(offset))
            if done(offset) { data.setStatus(.done, habitID: habit.id, day: key) }
            data.moods[key] = MoodEntry(level: mood(offset))
        }
    }

    private func impacts(_ insights: MoodJournal.Insights) -> [MoodJournal.Impact] {
        if case .ready(let list) = insights { return list }
        return []
    }

    func testNoEntriesNeedFourteenDays() {
        var data = AppData()
        data.habits = [habit("A")]
        XCTAssertEqual(MoodJournal.insights(in: data), .needMoreDays(14))
    }

    func testHabitThatGoesWithBetterMoodIsShown() throws {
        var data = AppData()
        let h = habit("A")
        data.habits = [h]
        // Через день: с привычкой 5, без неё 2.
        fill(&data, days: -20 ... -1, habit: h, done: { $0 % 2 == 0 }, mood: { $0 % 2 == 0 ? 5 : 2 })
        let top = impacts(MoodJournal.insights(in: data))
        let first = try XCTUnwrap(top.first)
        XCTAssertEqual(first.habit.id, h.id)
        XCTAssertEqual(first.delta, 3, accuracy: 0.001)
        XCTAssertEqual(first.doneDays, 10)
    }

    /// Шесть дней с привычкой - мало: нужно примерно 7 с каждой стороны. Показываем, сколько ещё.
    func testTooFewDaysOnOneSideShowsHowManyMore() {
        var data = AppData()
        let h = habit("A")
        data.habits = [h]
        fill(&data, days: -18 ... -1, habit: h, done: { $0 >= -6 }, mood: { $0 >= -6 ? 5 : 2 })
        // 6 дней с привычкой и 12 без: не хватает одного дня с привычкой.
        XCTAssertEqual(MoodJournal.insights(in: data), .needMoreDays(1))
    }

    func testFewEntriesCountRemainingDays() {
        var data = AppData()
        let h = habit("A")
        data.habits = [h]
        fill(&data, days: -4 ... -1, habit: h, done: { $0 % 2 == 0 }, mood: { _ in 4 })
        // 2 дня с привычкой и 2 без: не хватает 5 + 5.
        XCTAssertEqual(MoodJournal.insights(in: data), .needMoreDays(10))
    }

    /// Привычка с минусом не попадает в топ: карточка только о том, что идёт вместе с лучшим настроением.
    func testNegativeAndFlatHabitsAreNotShown() {
        var data = AppData()
        let worse = habit("Worse")
        data.habits = [worse]
        fill(&data, days: -20 ... -1, habit: worse, done: { $0 % 2 == 0 }, mood: { $0 % 2 == 0 ? 2 : 4 })
        XCTAssertEqual(MoodJournal.insights(in: data), .noLift)
    }

    /// Четыре привычки с плюсом, в карточке три с самым большим, при равенстве - в порядке списка.
    func testTopThreeSortedByLift() {
        var data = AppData()
        let a = habit("A", order: 0), b = habit("B", order: 1), c = habit("C", order: 2), d = habit("D", order: 3)
        data.habits = [d, c, b, a]
        // 60 дней подряд: остатки по 2, 3 и 5 независимы, поэтому разница средних ровно равна «весу» привычки.
        for offset in -60 ... -1 {
            let key = DayKey.make(day(offset))
            let doneA = offset % 2 == 0, doneB = offset % 3 == 0, doneC = offset % 5 == 0
            if doneA { data.setStatus(.done, habitID: a.id, day: key) }
            if doneB { data.setStatus(.done, habitID: b.id, day: key) }
            if doneC {
                data.setStatus(.done, habitID: c.id, day: key)
                data.setStatus(.done, habitID: d.id, day: key)
            }
            data.moods[key] = MoodEntry(level: 1 + (doneA ? 2 : 0) + (doneB ? 1 : 0) + (doneC ? 1 : 0))
        }
        let top = impacts(MoodJournal.insights(in: data))
        XCTAssertEqual(top.map(\.habit.name), ["A", "B", "C"])
        XCTAssertEqual(top.map { ($0.delta * 100).rounded() / 100 }, [2, 1, 1])
    }

    /// Сегодня привычку ещё могут отметить: сегодняшняя запись настроения не считается днём «без привычки».
    func testTodayIsNotCounted() throws {
        var data = AppData()
        let h = habit("A")
        data.habits = [h]
        fill(&data, days: -14 ... -1, habit: h, done: { $0 % 2 == 0 }, mood: { $0 % 2 == 0 ? 5 : 2 })
        // Сегодня настроение плохое, привычка ещё не отмечена: если бы день считался «без привычки», разница выросла бы.
        data.moods[DayKey.make(today)] = MoodEntry(level: 1)
        let first = try XCTUnwrap(impacts(MoodJournal.insights(in: data)).first)
        XCTAssertEqual(first.delta, 3, accuracy: 0.001)
    }

    /// Учитываются только дни по расписанию: по выходным привычки нет, и выходные не идут в «без привычки».
    func testOnlyScheduledDaysCount() throws {
        var data = AppData()
        var weekdays = habit("Weekdays")
        weekdays.schedule.weekdays = [2, 3, 4, 5, 6]
        data.habits = [weekdays]
        for offset in -35 ... -1 {
            let date = day(offset)
            let key = DayKey.make(date)
            let weekend = [1, 7].contains(calendar.component(.weekday, from: date))
            // Выходные всегда хорошие, но привычка тут ни при чём.
            if weekend {
                data.moods[key] = MoodEntry(level: 5)
            } else if offset % 2 == 0 {
                data.setStatus(.done, habitID: weekdays.id, day: key)
                data.moods[key] = MoodEntry(level: 4)
            } else {
                data.moods[key] = MoodEntry(level: 3)
            }
        }
        let first = try XCTUnwrap(impacts(MoodJournal.insights(in: data)).first)
        XCTAssertEqual(first.delta, 1, accuracy: 0.001)
    }

    func testQuitAndArchivedHabitsAreIgnored() {
        var data = AppData()
        var quit = habit("Quit")
        quit.quit = QuitInfo(startedAt: day(-60))
        var archived = habit("Archived")
        archived.isArchived = true
        data.habits = [quit, archived]
        fill(&data, days: -20 ... -1, habit: archived, done: { $0 % 2 == 0 }, mood: { $0 % 2 == 0 ? 5 : 2 })
        XCTAssertEqual(MoodJournal.insights(in: data), .noLift)
    }
}
