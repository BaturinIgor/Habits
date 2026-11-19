import XCTest
@testable import Habits

/// Синхронизация с Apple Watch: нажатие на часах, применение отметки на iPhone,
/// неподтверждённые отметки на часах (в том числе без связи).
final class WatchSyncTests: XCTestCase {
    private let calendar = Calendar.app
    private var todayKey: String { DayKey.make(Date()) }

    private func habit(_ name: String = "Test", target: Int? = nil) -> Habit {
        var habit = Habit(name: name, schedule: HabitSchedule(startDate: calendar.date(byAdding: .day, value: -10, to: Date())!),
                          createdAt: calendar.date(byAdding: .day, value: -10, to: Date())!)
        habit.target = target
        return habit
    }

    private func watchHabit(id: UUID = UUID(), target: Int = 1, count: Int = 0, done: Bool = false) -> WatchHabit {
        WatchHabit(id: id, name: "Test", emoji: nil, symbol: "star", colorIndex: 0,
                   target: target, count: count, done: done, skipped: false, timerMinutes: nil)
    }

    private func snapshot(_ habits: [WatchHabit], day: String, at: Date = Date(), acks: [String: Date]? = nil) -> WatchSnapshot {
        WatchSnapshot(generatedAt: at, isPro: true, days: [WatchDay(day: day, habits: habits)], acks: acks)
    }

    // MARK: Нажатие на часах

    func testTapTogglesSimpleHabit() {
        let habit = watchHabit()
        let done = habit.tapped()
        XCTAssertTrue(done.done)
        XCTAssertEqual(done.count, 1)
        XCTAssertFalse(done.tapped().done)
    }

    func testTapStepsCountHabitAndResetsAfterTarget() {
        var habit = watchHabit(target: 3)
        habit = habit.tapped()
        XCTAssertEqual(habit.count, 1)
        XCTAssertFalse(habit.done)
        habit = habit.tapped().tapped()
        XCTAssertTrue(habit.done)
        XCTAssertEqual(habit.count, 3)
        habit = habit.tapped()
        XCTAssertFalse(habit.done)
        XCTAssertEqual(habit.count, 0)
    }

    // MARK: Отметка на iPhone

    func testWatchMarkChecksOffAndUnchecks() {
        var data = AppData()
        let h = habit()
        data.habits = [h]
        let mark = WatchMark(habitID: h.id, day: todayKey, done: true, count: 1, at: Date())
        XCTAssertTrue(data.applyWatchMark(mark))
        XCTAssertEqual(data.status(h.id, day: todayKey), .done)
        // Повторная доставка той же отметки ничего не меняет.
        XCTAssertFalse(data.applyWatchMark(mark))

        let undo = WatchMark(habitID: h.id, day: todayKey, done: false, count: 0, at: Date().addingTimeInterval(1))
        XCTAssertTrue(data.applyWatchMark(undo))
        XCTAssertNil(data.status(h.id, day: todayKey))
        XCTAssertNil(data.checkIns[AppData.key(h.id, todayKey)])
    }

    func testLaterIPhoneChangeWinsOverOlderWatchMark() {
        var data = AppData()
        let h = habit()
        data.habits = [h]
        // Часы отметили без связи час назад, а на iPhone привычку отметили пропущенной уже после.
        let offlineMark = WatchMark(habitID: h.id, day: todayKey, done: true, count: 1, at: Date().addingTimeInterval(-3600))
        data.setStatus(.skipped, habitID: h.id, day: todayKey)
        XCTAssertFalse(data.applyWatchMark(offlineMark))
        XCTAssertEqual(data.status(h.id, day: todayKey), .skipped)
    }

    func testCountMarkKeepsProgress() {
        var data = AppData()
        data.settings.proUnlocked = true
        let h = habit(target: 5)
        data.habits = [h]
        let mark = WatchMark(habitID: h.id, day: todayKey, done: false, count: 2, at: Date())
        XCTAssertTrue(data.applyWatchMark(mark))
        XCTAssertNil(data.status(h.id, day: todayKey))
        XCTAssertEqual(data.count(of: h, day: todayKey), 2)
    }

    @MainActor
    func testSnapshotHasTodayAndTomorrow() {
        var data = AppData()
        data.settings.proUnlocked = true
        let h = habit(target: 4)
        data.habits = [h]
        data.tap(habitID: h.id, day: todayKey)
        let snapshot = WatchSnapshot.make(from: data)
        XCTAssertEqual(snapshot.days.count, 2)
        XCTAssertEqual(snapshot.days.first?.day, todayKey)
        let item = snapshot.days.first?.habits.first
        XCTAssertEqual(item?.target, 4)
        XCTAssertEqual(item?.count, 1)
        XCTAssertEqual(item?.done, false)
    }

    // MARK: Неподтверждённые отметки на часах

    func testPendingMarkIsShownOverSnapshot() {
        let h = watchHabit()
        var state = WatchState()
        state.receive(snapshot([h], day: todayKey))
        let mark = WatchMark(habitID: h.id, day: todayKey, done: true, count: 1, at: Date())
        state.pending[mark.key] = mark
        XCTAssertEqual(state.day(todayKey)?.habits.first?.done, true)
        XCTAssertEqual(state.day(todayKey)?.doneCount, 1)
    }

    func testOfflineMarkSurvivesNewerSnapshotUntilAcked() {
        let h = watchHabit()
        var state = WatchState()
        let mark = WatchMark(habitID: h.id, day: todayKey, done: true, count: 1, at: Date().addingTimeInterval(-3 * 3600))
        state.pending[mark.key] = mark
        // iPhone прислал снимок намного позже, но отметку ещё не получил.
        state.receive(snapshot([h], day: todayKey))
        XCTAssertNotNil(state.pending[mark.key])
        XCTAssertEqual(state.day(todayKey)?.habits.first?.done, true)

        // iPhone получил отметку, но на нём отметили иначе позже: часы показывают то, что на iPhone.
        state.receive(snapshot([h], day: todayKey, at: Date().addingTimeInterval(1), acks: [mark.key: mark.at]))
        XCTAssertNil(state.pending[mark.key])
        XCTAssertEqual(state.day(todayKey)?.habits.first?.done, false)
    }

    func testAckForOlderMarkKeepsNewerPending() {
        let h = watchHabit()
        var state = WatchState()
        let mark = WatchMark(habitID: h.id, day: todayKey, done: true, count: 1, at: Date())
        state.pending[mark.key] = mark
        state.receive(snapshot([h], day: todayKey, acks: [mark.key: mark.at.addingTimeInterval(-10)]))
        XCTAssertNotNil(state.pending[mark.key])
    }

    func testAppliedMarkIsDropped() {
        let id = UUID()
        var state = WatchState()
        let mark = WatchMark(habitID: id, day: todayKey, done: true, count: 1, at: Date())
        state.pending[mark.key] = mark
        state.receive(snapshot([watchHabit(id: id, count: 1, done: true)], day: todayKey))
        XCTAssertTrue(state.pending.isEmpty)
    }

    func testOlderSnapshotIsIgnored() {
        let h = watchHabit()
        var state = WatchState()
        state.receive(snapshot([h], day: todayKey))
        state.receive(snapshot([], day: todayKey, at: Date().addingTimeInterval(-60)))
        XCTAssertEqual(state.snapshot?.days.first?.habits.count, 1)
    }

    func testStateRoundTripsWithoutAcks() throws {
        // Снимок без поля acks (как от прошлой сборки) читается.
        let json = #"{"generatedAt":0,"isPro":false,"days":[]}"#
        let decoded = try JSONDecoder().decode(WatchSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(decoded.acks)
    }
}
