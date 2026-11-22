import XCTest
@testable import Habits

/// Умное время напоминаний (KAN-135): обычное время отметки, предложение сдвинуть, автосдвиг.
@MainActor
final class SmartTimeTests: XCTestCase {
    private static let moscow = TimeZone(identifier: "Europe/Moscow")!
    private static let newYork = TimeZone(identifier: "America/New_York")!

    private func calendar(_ zone: TimeZone = moscow) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// Воскресенье, 22 ноября 2026, полдень по Москве.
    private var now: Date {
        calendar().date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 12))!
    }

    private func day(_ offset: Int, _ cal: Calendar? = nil) -> Date {
        let cal = cal ?? calendar()
        return cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
    }

    private func habit(reminder: ReminderTime = ReminderTime(hour: 7, minute: 0)) -> Habit {
        Habit(name: "Test", schedule: HabitSchedule(startDate: day(-60)), reminder: reminder, createdAt: day(-60))
    }

    /// Отметка «выполнено» в этот день в hour:minute по местным часам пояса `zone`.
    private func check(_ data: inout AppData, _ habit: Habit, offset: Int, _ hour: Int, _ minute: Int,
                       zone: TimeZone = moscow, storeZone: Bool = true, markedOffset: Int? = nil) {
        let cal = calendar(zone)
        let markDay = day(markedOffset ?? offset, cal)
        let date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: markDay)!
        let key = DayKey.make(day(offset, cal), calendar: cal)
        data.checkIns[AppData.key(habit.id, key)] = CheckIn(
            status: .done, note: nil, updatedAt: date,
            tz: storeZone ? zone.secondsFromGMT(for: date) : nil
        )
    }

    private func data(with habit: Habit) -> AppData {
        var data = AppData()
        data.habits = [habit]
        return data
    }

    // MARK: Расчёт

    func testMedianOfEvenAndOddCounts() {
        XCTAssertNil(SmartTime.median([]))
        XCTAssertEqual(SmartTime.median([3, 1, 2]), 2)
        XCTAssertEqual(SmartTime.median([1, 2, 3, 10]), 2)
    }

    func testTooFewCheckInsGiveNoSuggestion() {
        let h = habit()
        var d = data(with: h)
        for offset in -5 ... -1 { check(&d, h, offset: offset, 8, 30) }
        XCTAssertEqual(SmartTime.samples(for: h, in: d, now: now, calendar: calendar()).count, 5)
        XCTAssertNil(SmartTime.suggestion(for: h, in: d, now: now, calendar: calendar()))
        XCTAssertEqual(SmartTime.missingSamples(SmartTime.samples(for: h, in: d, now: now, calendar: calendar())), 1)
    }

    func testSuggestsLaterTimeWhenAlwaysCheckedLater() throws {
        let h = habit()
        var d = data(with: h)
        for offset in -14 ... -1 { check(&d, h, offset: offset, 8, 30) }
        let suggestion = try XCTUnwrap(SmartTime.suggestion(for: h, in: d, now: now, calendar: calendar()))
        XCTAssertEqual(suggestion.typical, ReminderTime(hour: 8, minute: 30))
        XCTAssertEqual(suggestion.suggested, ReminderTime(hour: 8, minute: 20))
        XCTAssertEqual(suggestion.shiftMinutes, 80)
    }

    func testSuggestsEarlierTimeWhenCheckedBeforeReminder() throws {
        let h = habit(reminder: ReminderTime(hour: 21, minute: 0))
        var d = data(with: h)
        for offset in -14 ... -1 { check(&d, h, offset: offset, 8, 2) }
        let suggestion = try XCTUnwrap(SmartTime.suggestion(for: h, in: d, now: now, calendar: calendar()))
        // 8:02 - 10 минут = 7:52, округление до 5 минут.
        XCTAssertEqual(suggestion.suggested, ReminderTime(hour: 7, minute: 50))
        XCTAssertLessThan(suggestion.shiftMinutes, 0)
    }

    func testSmallDifferenceGivesNoSuggestion() {
        let h = habit(reminder: ReminderTime(hour: 8, minute: 0))
        var d = data(with: h)
        for offset in -14 ... -1 { check(&d, h, offset: offset, 8, 30) }
        XCTAssertNil(SmartTime.suggestion(for: h, in: d, now: now, calendar: calendar()))
    }

    /// По будням в 8:00, по выходным в 11:00: обычное время - будничное, выходные его не перетягивают.
    func testWeekendsDoNotPullTypicalTime() throws {
        let h = habit(reminder: ReminderTime(hour: 6, minute: 30))
        var d = data(with: h)
        let cal = calendar()
        for offset in -21 ... -1 {
            let weekend = [1, 7].contains(cal.component(.weekday, from: day(offset)))
            check(&d, h, offset: offset, weekend ? 11 : 8, 0)
        }
        let suggestion = try XCTUnwrap(SmartTime.suggestion(for: h, in: d, now: now, calendar: cal))
        XCTAssertEqual(suggestion.typical, ReminderTime(hour: 8, minute: 0))
        XCTAssertEqual(suggestion.suggested, ReminderTime(hour: 7, minute: 50))
    }

    /// Часть дней недели раньше напоминания, часть позже: стабильной разницы нет.
    func testUnstablePatternGivesNoSuggestion() {
        let h = habit(reminder: ReminderTime(hour: 8, minute: 0))
        var d = data(with: h)
        let cal = calendar()
        for offset in -21 ... -1 {
            let weekday = cal.component(.weekday, from: day(offset))
            check(&d, h, offset: offset, [2, 3, 4].contains(weekday) ? 10 : 6, 30)
        }
        XCTAssertNil(SmartTime.suggestion(for: h, in: d, now: now, calendar: cal))
    }

    /// Две случайные отметки поздно вечером не сдвигают обычное время.
    func testOutliersAreIgnored() throws {
        let h = habit()
        var d = data(with: h)
        for offset in -14 ... -1 { check(&d, h, offset: offset, 8, 30) }
        // Два понедельника подряд (9 и 16 ноября) в 23:50: без отсева медиана понедельника ушла бы на ночь.
        check(&d, h, offset: -13, 23, 50)
        check(&d, h, offset: -6, 23, 50)
        let samples = SmartTime.samples(for: h, in: d, now: now, calendar: calendar())
        XCTAssertEqual(SmartTime.typicalMinutes(samples), 8 * 60 + 30)
        let suggestion = try XCTUnwrap(SmartTime.suggestion(for: h, in: d, now: now, calendar: calendar()))
        XCTAssertEqual(suggestion.suggested, ReminderTime(hour: 8, minute: 20))
    }

    /// Отметка задним числом (поставлена на следующий день) ничего не говорит о времени привычки.
    func testBackfilledCheckInsAreIgnored() {
        let h = habit()
        var d = data(with: h)
        for offset in -14 ... -1 { check(&d, h, offset: offset, 8, 30, markedOffset: offset + 1) }
        XCTAssertTrue(SmartTime.samples(for: h, in: d, now: now, calendar: calendar()).isEmpty)
        XCTAssertNil(SmartTime.suggestion(for: h, in: d, now: now, calendar: calendar()))
    }

    /// Отметки старше трёх недель не учитываются.
    func testOldCheckInsOutsideWindowAreIgnored() {
        let h = habit()
        var d = data(with: h)
        for offset in -40 ... -22 { check(&d, h, offset: offset, 8, 30) }
        XCTAssertTrue(SmartTime.samples(for: h, in: d, now: now, calendar: calendar()).isEmpty)
    }

    /// Отметки в Москве в 8:30, потом человек улетел в Нью-Йорк: время считается по местным часам отметки,
    /// а не переводится в новый пояс (там это было бы 0:30).
    func testTimeZoneChangeKeepsLocalTimeOfCheckIn() throws {
        let h = habit()
        var d = data(with: h)
        for offset in -14 ... -1 { check(&d, h, offset: offset, 8, 30, zone: Self.moscow) }
        let suggestion = try XCTUnwrap(SmartTime.suggestion(for: h, in: d, now: now, calendar: calendar(Self.newYork)))
        XCTAssertEqual(suggestion.typical, ReminderTime(hour: 8, minute: 30))
        XCTAssertEqual(suggestion.suggested, ReminderTime(hour: 8, minute: 20))
    }

    /// Старые отметки без пояса считаются по текущему поясу.
    func testCheckInsWithoutZoneUseCurrentCalendar() throws {
        let h = habit()
        var d = data(with: h)
        for offset in -14 ... -1 { check(&d, h, offset: offset, 8, 30, storeZone: false) }
        let suggestion = try XCTUnwrap(SmartTime.suggestion(for: h, in: d, now: now, calendar: calendar()))
        XCTAssertEqual(suggestion.typical, ReminderTime(hour: 8, minute: 30))
    }

    func testSkippedAndAutoCheckedHabitsAreNotUsed() {
        var h = habit()
        var d = data(with: h)
        for offset in -14 ... -1 {
            check(&d, h, offset: offset, 8, 30)
            d.checkIns[AppData.key(h.id, DayKey.make(day(offset), calendar: calendar()))]?.status = .skipped
        }
        XCTAssertNil(SmartTime.suggestion(for: h, in: d, now: now, calendar: calendar()))
        // Здоровье отмечает само: время отметки не про человека.
        h.health = HealthLink(metric: .steps, goal: 10_000)
        XCTAssertFalse(SmartTime.isEligible(h))
        h.health = nil
        h.reminder = nil
        XCTAssertFalse(SmartTime.isEligible(h))
    }

    // MARK: Автосдвиг

    func testAutoShiftOnlyWithSmartTimeOn() {
        var h = habit()
        var d = data(with: h)
        for offset in -14 ... -1 { check(&d, h, offset: offset, 8, 30) }
        XCTAssertTrue(d.applySmartTimes(now: now, calendar: calendar()).isEmpty)
        XCTAssertEqual(d.habits[0].reminder, ReminderTime(hour: 7, minute: 0))

        h.smartTime = true
        d.habits = [h]
        let shifted = d.applySmartTimes(now: now, calendar: calendar())
        XCTAssertEqual(shifted.count, 1)
        XCTAssertEqual(shifted.first?.shift, 80)
        XCTAssertEqual(d.habits[0].reminder, ReminderTime(hour: 8, minute: 20))
        // После сдвига время уже близко к обычному: второй раз не двигаем.
        XCTAssertTrue(d.applySmartTimes(now: now, calendar: calendar()).isEmpty)
    }

    /// После сдвига остаются повторы каждые 15 минут и категория с кнопками «Готово» и «Пропустить».
    func testShiftedReminderKeepsRepeats() {
        let cal = Calendar.app
        let today = cal.startOfDay(for: Date())
        var h = Habit(name: "Test", schedule: HabitSchedule(startDate: today), reminder: ReminderTime(hour: 8, minute: 20), createdAt: today)
        h.smartTime = true
        var d = AppData()
        d.settings.summaryEnabled = false
        d.settings.badgeEnabled = false
        d.habits = [h]
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let events = NotificationPlanner.plan(data: d, now: today.addingTimeInterval(-3600))
            .filter { $0.habit?.id == h.id && $0.day == DayKey.make(tomorrow) }
        XCTAssertEqual(events.map(\.index), [0, 1, 2, 3])
        let first = ReminderTime(hour: 8, minute: 20).date(on: tomorrow)!
        XCTAssertEqual(events.map(\.date), (0...3).map { first.addingTimeInterval(Double($0) * 15 * 60) })
    }

    // MARK: Формат данных

    func testSmartTimeFieldIsBackwardCompatible() throws {
        var h = habit()
        // Выключено: поля нет в JSON, старые версии и семейная синхронизация видят ту же привычку.
        let plain = try JSONEncoder().encode(h)
        let plainJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        XCTAssertNil(plainJSON["smartTime"])
        XCTAssertNil(try JSONDecoder().decode(Habit.self, from: plain).smartTime)

        h.smartTime = true
        let encoded = try JSONEncoder().encode(h)
        XCTAssertEqual(try JSONDecoder().decode(Habit.self, from: encoded).smartTime, true)

        // Мусор в поле не ломает привычку.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json["smartTime"] = "yes"
        let broken = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Habit.self, from: broken)
        XCTAssertNil(decoded.smartTime)
        XCTAssertEqual(decoded.id, h.id)
    }

    func testCheckInRemembersTimeZone() throws {
        var d = data(with: habit())
        let key = DayKey.make(Date())
        d.setStatus(.done, habitID: d.habits[0].id, day: key)
        XCTAssertEqual(d.checkIn(d.habits[0].id, day: key)?.tz, TimeZone.current.secondsFromGMT())
        // Старая отметка без пояса читается.
        let old = try JSONDecoder().decode(CheckIn.self, from: Data(#"{"status":"done","updatedAt":0}"#.utf8))
        XCTAssertNil(old.tz)
    }

    func testSmartTimeAnalyticsNames() {
        let events: [AnalyticsEvent] = [
            .smartTimeSuggested(shiftMinutes: 80), .smartTimeAccepted(shiftMinutes: -30),
            .smartTimeDismissed(shiftMinutes: 45), .smartTimeAutoShifted(shiftMinutes: 60),
        ]
        XCTAssertEqual(events.map { Analytics.firebaseName($0.type) },
                       ["smart_time_suggested", "smart_time_accepted", "smart_time_dismissed", "smart_time_auto_shifted"])
        for event in events {
            XCTAssertEqual(Analytics.firebaseParameters(event.payload).keys.sorted(), ["smart_time_shift_minutes"])
        }
    }
}
