import CoreImage
import SwiftUI
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
        let recap = Recap.lastWeek(in: data)
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
        let recap = Recap.lastWeek(in: AppData())
        XCTAssertFalse(recap.hasData)
        XCTAssertEqual(recap.percent, 0)
        XCTAssertNil(recap.top)
    }

    // MARK: Ссылка на App Store при шеринге (1.6)

    func testShareLinkPointsToAppStore() {
        // Без provider token Apple метки не считает, поэтому их нет.
        let plain = AppInfo.appStoreURL(campaign: .weekly, providerToken: "")
        XCTAssertEqual(plain.host, "apps.apple.com")
        XCTAssertEqual(plain.path, "/app/id\(AppInfo.appStoreID)")
        XCTAssertNil(plain.query)

        let tagged = AppInfo.appStoreURL(campaign: .month, providerToken: "123456")
        XCTAssertEqual(tagged.path, "/app/id\(AppInfo.appStoreID)")
        let items = URLComponents(url: tagged, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(Set(items), [
            URLQueryItem(name: "pt", value: "123456"),
            URLQueryItem(name: "ct", value: "share_month"),
            URLQueryItem(name: "mt", value: "8"),
        ])

        let url = AppInfo.appStoreURL(campaign: .weekly)
        XCTAssertTrue(ShareSheet.message(campaign: .weekly).hasSuffix(" " + url.absoluteString))
    }

    /// Длинная ссылка с метками (когда появится provider token) тоже даёт читаемый QR-код.
    @MainActor
    func testTaggedLinkQRCodeIsReadable() throws {
        let link = AppInfo.appStoreURL(campaign: .achievement, providerToken: "118727439").absoluteString
        let renderer = ImageRenderer(content:
            qrBlock(link)
                .padding(20)
                .background(LinearGradient(colors: [.indigo, .purple], startPoint: .top, endPoint: .bottom))
        )
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.cgImage)
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let codes = detector.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertEqual(codes, [link])
    }

    @MainActor
    private func qrBlock(_ link: String) -> some View {
        let qr = QRCode(link)!
        let module = qr.modulePoints(fitting: 88)
        return Image(uiImage: qr.image)
            .interpolation(.none)
            .resizable()
            .frame(width: module * CGFloat(qr.modules), height: module * CGFloat(qr.modules))
            .padding(module * 3)
            .background(Color.white)
    }

    /// QR-код на картинке «Итогов недели» читается и ведёт в App Store.
    @MainActor
    func testWeeklyRecapShareImageHasReadableQRCode() throws {
        var data = AppData()
        data.habits = [dailyHabit(startOffset: -40)]
        XCTAssertEqual(try qrCodes(onShareImageOf: Recap.lastWeek(in: data)), [AppInfo.appStoreURL(campaign: .weekly).absoluteString])
    }

    /// QR-коды на картинках «Итогов месяца» и «Итогов года» читаются и несут свои метки кампании.
    @MainActor
    func testMonthAndYearRecapShareImagesHaveReadableQRCode() throws {
        var data = AppData()
        let habit = dailyHabit(startOffset: -400)
        data.habits = [habit]
        for offset in -400 ... -1 where offset % 3 != 0 {
            data.setStatus(.done, habitID: habit.id, day: DayKey.make(day(offset)))
        }
        for period in [Recap.Period.month, .year] {
            let recap = Recap.current(period, in: data)
            XCTAssertTrue(recap.hasData, "\(period)")
            XCTAssertEqual(try qrCodes(onShareImageOf: recap), [AppInfo.appStoreURL(campaign: period.campaign).absoluteString], "\(period)")
        }
    }

    @MainActor
    private func qrCodes(onShareImageOf recap: Recap) throws -> [String] {
        let renderer = ImageRenderer(content: RecapCard.shareImageContent(recap))
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.cgImage)
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        return detector.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }

    // MARK: Итоги месяца и года (1.6)

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func habit(from start: Date) -> Habit {
        Habit(name: "Test", schedule: HabitSchedule(startDate: start), createdAt: start)
    }

    func testMonthlyRecapCountsLastFullMonth() {
        var data = AppData()
        let habit = habit(from: date(2026, 1, 1))
        data.habits = [habit]
        // Февраль 2026 (28 дней): пропущены 10, 11 и 12, 20-е пропущено по уважительной причине.
        for d in 1 ... 28 where ![10, 11, 12, 20].contains(d) {
            data.setStatus(.done, habitID: habit.id, day: DayKey.make(date(2026, 2, d)))
        }
        data.setStatus(.skipped, habitID: habit.id, day: DayKey.make(date(2026, 2, 20)))
        // Отметки за соседние месяцы в итоги февраля не попадают.
        data.setStatus(.done, habitID: habit.id, day: DayKey.make(date(2026, 1, 31)))
        data.setStatus(.done, habitID: habit.id, day: DayKey.make(date(2026, 3, 1)))

        let recap = Recap.lastMonth(in: data, now: date(2026, 3, 15))
        XCTAssertEqual(recap.period, .month)
        XCTAssertEqual(recap.start, calendar.startOfDay(for: date(2026, 2, 1)))
        XCTAssertEqual(recap.end, calendar.startOfDay(for: date(2026, 2, 28)))
        XCTAssertEqual(recap.days.count, 28)
        XCTAssertEqual(recap.bars.count, 28)
        XCTAssertEqual(recap.done, 24)
        XCTAssertEqual(recap.total, 27)
        XCTAssertEqual(recap.perfectDays, 24)
        XCTAssertEqual(recap.percent, 89)
        // 1–9 февраля, 10 и 11 спасли заморозки, 12-е прервало серию; потом 13–28 без 20-го (пропуск не рвёт).
        XCTAssertEqual(recap.streak, 15)
        XCTAssertEqual(recap.streakName, "Test")
        XCTAssertEqual(recap.top, Recap.Top(name: "Test", done: 24, total: 27))
        XCTAssertTrue(recap.isComplete)
    }

    func testYearlyRecapShowsLastFullYearWithTwelveMonths() {
        var data = AppData()
        let habit = habit(from: date(2025, 1, 1))
        data.habits = [habit]
        for d in 1 ... 31 {
            data.setStatus(.done, habitID: habit.id, day: DayKey.make(date(2025, 3, d)))
        }
        let recap = Recap.year(in: data, now: date(2026, 3, 15))
        XCTAssertEqual(recap.start, calendar.startOfDay(for: date(2025, 1, 1)))
        XCTAssertEqual(recap.end, calendar.startOfDay(for: date(2025, 12, 31)))
        XCTAssertTrue(recap.isComplete)
        XCTAssertEqual(recap.days.count, 365)
        XCTAssertEqual(recap.bars.count, 12)
        XCTAssertEqual(recap.bars[0].done, 0)
        XCTAssertEqual(recap.bars[0].total, 31)
        XCTAssertEqual(recap.bars[2].done, 31)
        XCTAssertEqual(recap.bars[2].fraction, 1)
        XCTAssertEqual(recap.bars[1].total, 28)
        XCTAssertEqual(recap.done, 31)
        XCTAssertEqual(recap.total, 365)
        XCTAssertEqual(recap.perfectDays, 31)
        XCTAssertEqual(recap.percent, 8)
        XCTAssertEqual(recap.streak, 31)
        XCTAssertEqual(recap.top?.done, 31)
    }

    func testYearlyRecapInDecemberIsYearToDate() {
        var data = AppData()
        let habit = habit(from: date(2025, 6, 1))
        data.habits = [habit]
        data.setStatus(.done, habitID: habit.id, day: DayKey.make(date(2026, 12, 9)))
        // Сегодняшняя отметка в итоги не идёт: день ещё не закончился.
        data.setStatus(.done, habitID: habit.id, day: DayKey.make(date(2026, 12, 10)))
        let recap = Recap.year(in: data, now: date(2026, 12, 10))
        XCTAssertEqual(recap.start, calendar.startOfDay(for: date(2026, 1, 1)))
        XCTAssertEqual(recap.end, calendar.startOfDay(for: date(2026, 12, 9)))
        XCTAssertFalse(recap.isComplete)
        XCTAssertEqual(recap.bars.count, 12)
        XCTAssertEqual(recap.bars[11].total, 9)
        XCTAssertEqual(recap.bars[11].done, 1)
        XCTAssertEqual(recap.done, 1)
    }

    func testYearlyRecapFallsBackToThisYearWithoutLastYearData() {
        var data = AppData()
        let habit = habit(from: date(2026, 2, 1))
        data.habits = [habit]
        let recap = Recap.year(in: data, now: date(2026, 3, 15))
        XCTAssertEqual(recap.start, calendar.startOfDay(for: date(2026, 1, 1)))
        XCTAssertEqual(recap.end, calendar.startOfDay(for: date(2026, 3, 14)))
        XCTAssertFalse(recap.isComplete)
        // Февраль и 14 дней марта.
        XCTAssertEqual(recap.total, 28 + 14)
        XCTAssertEqual(recap.bars[3].total, 0)
    }

    func testMonthAndYearRecapsAreEmptyWithoutHabits() {
        for period in [Recap.Period.month, .year] {
            let recap = Recap.current(period, in: AppData())
            XCTAssertFalse(recap.hasData, "\(period)")
            XCTAssertEqual(recap.percent, 0)
            XCTAssertEqual(recap.perfectDays, 0)
            XCTAssertEqual(recap.streak, 0)
            XCTAssertNil(recap.streakName)
            XCTAssertNil(recap.top)
        }
        XCTAssertEqual(Recap.year(in: AppData()).bars.count, 12)
    }

    /// Порог «самой стабильной» считается от нужных дней самой привычки: привычка по понедельникам
    /// может победить в месяце, а заведённая во второй половине периода не обходит старые.
    func testMostSteadyAcceptsWeekdayHabitAndSkipsLateNewcomer() {
        var data = AppData()
        let daily = habit(from: date(2026, 1, 1))
        var mondays = Habit(name: "Mondays", schedule: HabitSchedule(weekdays: [2], startDate: date(2026, 1, 1)), createdAt: date(2026, 1, 1))
        mondays.sortOrder = 1
        var late = Habit(name: "Late", schedule: HabitSchedule(startDate: date(2026, 2, 20)), createdAt: date(2026, 2, 20))
        late.sortOrder = 2
        data.habits = [daily, mondays, late]
        for d in 1 ... 28 {
            let key = DayKey.make(date(2026, 2, d))
            if d != 14 { data.setStatus(.done, habitID: daily.id, day: key) }
            if [2, 9, 16, 23].contains(d) { data.setStatus(.done, habitID: mondays.id, day: key) }
            if d >= 20 { data.setStatus(.done, habitID: late.id, day: key) }
        }
        let recap = Recap.lastMonth(in: data, now: date(2026, 3, 15))
        XCTAssertEqual(recap.top, Recap.Top(name: "Mondays", done: 4, total: 4))
    }

    /// Карточка на «Сегодня» сохраняет текущую серию у недели (а не серию внутри недели).
    func testWeeklyRecapKeepsCurrentStreak() {
        var data = AppData()
        let habit = dailyHabit(startOffset: -40)
        data.habits = [habit]
        for offset in -19 ... 0 {
            data.setStatus(.done, habitID: habit.id, day: DayKey.make(day(offset)))
        }
        let recap = Recap.lastWeek(in: data)
        XCTAssertEqual(recap.streak, 20)
        XCTAssertEqual(recap.streakName, "Test")
    }

    func testYearRecapAroundNewYear() {
        var data = AppData()
        data.habits = [habit(from: date(2026, 1, 1))]
        // 31 декабря: текущий год по 30 декабря.
        let december = Recap.interval(.year, in: data, now: date(2026, 12, 31))
        XCTAssertEqual(december, Recap.Interval(start: calendar.startOfDay(for: date(2026, 1, 1)), end: calendar.startOfDay(for: date(2026, 12, 30))))
        XCTAssertTrue(Recap.isAvailable(.year, in: data, now: date(2026, 12, 31)))
        // 1 января: прошлый полный год.
        let newYear = Recap.year(in: data, now: date(2027, 1, 1))
        XCTAssertEqual(newYear.start, calendar.startOfDay(for: date(2026, 1, 1)))
        XCTAssertEqual(newYear.end, calendar.startOfDay(for: date(2026, 12, 31)))
        XCTAssertTrue(newYear.isComplete)
        XCTAssertTrue(newYear.hasData)

        // Привычки только с нового года: 1 января итоги года пустые, 3 января в них два дня.
        // В «Статистике» их не предлагаем.
        var fresh = AppData()
        fresh.habits = [habit(from: date(2027, 1, 1))]
        XCTAssertFalse(Recap.year(in: fresh, now: date(2027, 1, 1)).hasData)
        XCTAssertFalse(Recap.isAvailable(.year, in: fresh, now: date(2027, 1, 1)))
        XCTAssertEqual(Recap.year(in: fresh, now: date(2027, 1, 3)).days.count, 2)
        XCTAssertFalse(Recap.isAvailable(.year, in: fresh, now: date(2027, 1, 3)))
        XCTAssertFalse(Recap.isAvailable(.month, in: fresh, now: date(2027, 1, 3)))
        XCTAssertTrue(Recap.isAvailable(.year, in: fresh, now: date(2027, 1, 9)))
    }

    func testBannerCandidatesPickPeriodByDay() {
        // Неделя с понедельника, чтобы тест не зависел от региона симулятора.
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = .current
        func at(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
        func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.startOfDay(for: at(y, m, d)) }
        func candidates(_ now: Date, dismissed: [Recap.Period: String] = [:]) -> [Recap.BannerCandidate] {
            Recap.bannerCandidates(dismissed: dismissed, now: now, calendar: cal)
        }
        func interval(_ a: Date, _ b: Date) -> Recap.Interval { Recap.Interval(start: a, end: b) }

        // 1 января 2026 (четверг): прошлый год, затем декабрь. Неделя началась 29 декабря, это уже 4-й день.
        XCTAssertEqual(candidates(at(2026, 1, 1)), [
            .init(period: .year, interval: interval(day(2025, 1, 1), day(2025, 12, 31))),
            .init(period: .month, interval: interval(day(2025, 12, 1), day(2025, 12, 31))),
        ])
        // 3-е число ещё с итогами месяца, 4-е уже без них.
        XCTAssertEqual(candidates(at(2026, 3, 3)).map(\.period), [.month, .week])
        XCTAssertEqual(candidates(at(2026, 3, 4)).map(\.period), [.week])
        XCTAssertEqual(candidates(at(2026, 3, 5)), [])
        // Понедельник 1 июня: месяц важнее недели, а если месяц закрыли, остаётся неделя.
        XCTAssertEqual(candidates(at(2026, 6, 1)), [
            .init(period: .month, interval: interval(day(2026, 5, 1), day(2026, 5, 31))),
            .init(period: .week, interval: interval(day(2026, 5, 25), day(2026, 5, 31))),
        ])
        XCTAssertEqual(candidates(at(2026, 6, 1), dismissed: [.month: "2026-05-01"]).map(\.period), [.week])
        XCTAssertEqual(candidates(at(2026, 6, 1), dismissed: [.month: "2026-05-01", .week: "2026-05-25"]), [])
        // Прошлогодний ключ не мешает итогам нового месяца.
        XCTAssertEqual(candidates(at(2026, 6, 1), dismissed: [.month: "2026-04-01"]).first?.period, .month)
        // Високосный год: февраль 2024 до 29-го.
        XCTAssertEqual(candidates(at(2024, 3, 1)), [
            .init(period: .month, interval: interval(day(2024, 2, 1), day(2024, 2, 29))),
        ])
    }

    func testBannerTakesFirstPeriodWithData() {
        var data = AppData()
        let habit = habit(from: date(2026, 5, 25))
        data.habits = [habit]
        data.setStatus(.done, habitID: habit.id, day: DayKey.make(date(2026, 5, 26)))
        // 1 июня: за май привычка была (с 25-го), поэтому показываем месяц.
        XCTAssertEqual(Recap.banner(in: data, dismissed: [:], now: date(2026, 6, 1))?.period, .month)
        // Месяц закрыли: остаются итоги недели.
        let monthKey = DayKey.make(Recap.lastMonthInterval(now: date(2026, 6, 1)).start)
        let weekly = Recap.banner(in: data, dismissed: [.month: monthKey], now: date(2026, 6, 1))
        if Recap.bannerCandidates(dismissed: [:], now: date(2026, 6, 1)).contains(where: { $0.period == .week }) {
            XCTAssertEqual(weekly?.period, .week)
        } else {
            XCTAssertNil(weekly)
        }
        XCTAssertNil(Recap.banner(in: AppData(), dismissed: [:], now: date(2026, 6, 1)))
    }

    func testMonthTitleHasNoYearSuffix() {
        XCTAssertEqual(RecapCard.monthTitle(date(2026, 10, 1), locale: Locale(identifier: "ru")), "Октябрь 2026")
        XCTAssertEqual(RecapCard.monthTitle(date(2026, 10, 1), locale: Locale(identifier: "en")), "October 2026")
        XCTAssertEqual(RecapCard.monthTitle(date(2026, 10, 1), locale: Locale(identifier: "ja")), "2026年10月")
        XCTAssertEqual(RecapCard.monthTitle(date(2026, 10, 1), locale: Locale(identifier: "es")), "Octubre de 2026")
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

    // MARK: Настроение (1.5)

    func testMoodsSurviveOldFilesAndRoundTrip() throws {
        // Файл без поля moods (версии до 1.5) читается с пустым дневником.
        let old = try JSONSerialization.data(withJSONObject: ["version": 1, "habits": []])
        XCTAssertTrue(try JSONDecoder().decode(AppData.self, from: old).moods.isEmpty)

        var data = AppData()
        data.moods["2026-11-17"] = MoodEntry(level: 9, note: "ok")
        XCTAssertEqual(data.moods["2026-11-17"]?.level, 5, "оценка ограничена 1...5")
        let decoded = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(decoded.moods["2026-11-17"]?.note, "ok")
        XCTAssertFalse(decoded.settings.appLock)
        XCTAssertTrue(decoded.settings.moodCard)
    }

    func testMoodFreeWindowIsSevenDays() {
        XCTAssertTrue(MoodJournal.isFree(day(0), now: today))
        XCTAssertTrue(MoodJournal.isFree(day(-6), now: today))
        XCTAssertFalse(MoodJournal.isFree(day(-7), now: today))
    }

    func testMoodImpactFindsHabitThatLiftsMood() {
        var data = AppData()
        let habit = dailyHabit(startOffset: -20)
        data.habits = [habit]
        // Дни с привычкой: настроение 5, без неё: 2.
        for offset in -9 ... 0 {
            let key = DayKey.make(day(offset))
            if offset % 2 == 0 {
                data.setStatus(.done, habitID: habit.id, day: key)
                data.moods[key] = MoodEntry(level: 5)
            } else {
                data.moods[key] = MoodEntry(level: 2)
            }
        }
        let impacts = MoodJournal.impacts(in: data)
        XCTAssertEqual(impacts.first?.habit.id, habit.id)
        XCTAssertEqual(impacts.first?.delta ?? 0, 3, accuracy: 0.001)
        XCTAssertEqual(MoodJournal.average(in: data, days: 10, now: today) ?? 0, 3.5, accuracy: 0.001)
    }

    func testMoodImpactNeedsEnoughDays() {
        var data = AppData()
        let habit = dailyHabit(startOffset: -20)
        data.habits = [habit]
        for offset in -3 ... 0 {
            let key = DayKey.make(day(offset))
            data.setStatus(.done, habitID: habit.id, day: key)
            data.moods[key] = MoodEntry(level: 5)
        }
        XCTAssertTrue(MoodJournal.impacts(in: data).isEmpty)
    }

    // MARK: CSV (1.5)

    func testCSVEscapesAndSkipsEmptyRows() {
        var data = AppData()
        var habit = dailyHabit(startOffset: -3)
        habit.name = "Read, \"slowly\""
        data.habits = [habit]
        let yesterday = DayKey.make(day(-1))
        let todayKey = DayKey.make(day(0))
        data.setStatus(.done, habitID: habit.id, day: yesterday)
        data.setNote("line1\nline2", habitID: habit.id, day: yesterday)
        data.moods[yesterday] = MoodEntry(level: 4)
        // Отметку сняли: такая пустая запись в таблицу не попадает.
        data.setStatus(.done, habitID: habit.id, day: todayKey)
        data.setStatus(nil, habitID: habit.id, day: todayKey)

        let lines = CSVExport.make(from: data).components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2, "заголовок и одна строка")
        XCTAssertTrue(lines[1].hasPrefix(yesterday + ",\"Read, \"\"slowly\"\"\","))
        XCTAssertTrue(lines[1].contains(",4,"))
        XCTAssertTrue(lines[1].hasSuffix("\"line1\nline2\""))
    }
}
