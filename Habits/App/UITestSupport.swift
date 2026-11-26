import Foundation
import SwiftUI

#if DEBUG
/// Данные и проверки для автотестов интерфейса (HabitsUITests).
enum UITestSupport {
    /// Постоянные id, чтобы тесты находили карточки привычек.
    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    static var isRussian: Bool {
        Locale.preferredLanguages.first?.hasPrefix("ru") == true
    }

    /// Набор привычек с историей за месяц: обычные, количественная, с таймером, по будням,
    /// «N раз в неделю», «Бросаю» и привычка с длинным названием.
    static func demoData(now: Date = Date()) -> AppData {
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        // Скриншоты App Store (-design-store): история за два месяца, чтобы были итоги прошлого месяца.
        let span = TestMode.has("-design-store") ? 60 : 30
        let start = day(-span)
        let ru = isRussian

        var data = AppData()
        if TestMode.has("-uitest-onboarding") { return data }

        data.settings.onboardingDone = true
        data.settings.gestureHintShown = true
        // Бесплатная версия для макетов состояний «нет доступа».
        data.settings.proUnlocked = !TestMode.has("-uitest-free")
        data.settings.whatsNewSeen = TestMode.has("-uitest-whatsnew") ? "" : WhatsNewView.version
        data.settings.seenAchievements = Achievements.all.map(\.id)
        // Пустое приложение: макеты пустых состояний.
        if TestMode.has("-uitest-empty") { return data }
        // Первый день после онбординга (KAN-169): привычки программы «Энергия», отметок ещё нет
        // или (-uitest-firstday-checked) первая отметка только что сделана.
        if TestMode.has("-uitest-firstday") || TestMode.has("-uitest-firstday-checked") {
            data.settings.firstDayGuide = true
            data.settings.proUnlocked = false
            data.habits = OnboardingPlan.habits(for: .energy, isPro: false).enumerated().map { index, habit in
                var habit = habit
                habit.id = id(index + 1)
                habit.sortOrder = index
                habit.createdAt = today
                habit.schedule.startDate = today
                return habit
            }
            if TestMode.has("-uitest-firstday-checked"), let first = data.habits.first {
                data.setStatus(.done, habitID: first.id, day: DayKey.make(today))
            }
            return data
        }

        func habit(_ n: Int, _ en: String, _ ruName: String, icon: String, color: Int,
                   schedule: HabitSchedule = HabitSchedule(startDate: start),
                   reminder: ReminderTime? = nil, part: PartOfDay? = nil) -> Habit {
            var h = Habit(id: id(n), name: ru ? ruName : DemoText.t(en), icon: .symbol(icon), colorIndex: color,
                          schedule: schedule, reminder: reminder, createdAt: start, sortOrder: n, partOfDay: part)
            h.schedule.startDate = start
            return h
        }

        var exercise = habit(1, "Morning exercises", "Утренняя зарядка", icon: "figure.run", color: 0,
                             reminder: ReminderTime(hour: 7, minute: 30))
        exercise.minimumVersion = ru ? "Хотя бы 5 приседаний" : DemoText.t("At least 5 squats")
        var water = habit(2, "Drink water", "Пить воду", icon: "drop.fill", color: 3, part: .anytime)
        water.target = 8
        water.unit = ru ? "стаканов" : DemoText.t("glasses")
        var meditation = habit(3, "Meditation", "Медитация", icon: "brain.head.profile", color: 5,
                               reminder: ReminderTime(hour: 8, minute: 0))
        meditation.timerMinutes = 10
        let reading = habit(4, "Read 20 pages of a book before going to bed",
                            "Прочитать 20 страниц книги перед сном без телефона", icon: "book.fill", color: 2,
                            schedule: HabitSchedule(weekdays: [2, 3, 4, 5, 6], startDate: start), part: .evening)
        let gym = habit(5, "Gym", "Спортзал", icon: "dumbbell.fill", color: 1,
                        schedule: HabitSchedule(kind: .weekly, startDate: start, timesPerWeek: 3))
        var steps = habit(6, "Walk 10,000 steps", "Пройти 10 000 шагов", icon: "figure.walk", color: 4)
        steps.health = HealthLink(metric: .steps, goal: 10_000)
        var smoking = habit(7, "No smoking", "Не курить", icon: "nosign", color: 6, schedule: HabitSchedule(startDate: start))
        var quit = QuitInfo(startedAt: day(-40), dailyCost: 300)
        quit.relapse(at: day(-12))
        smoking.quit = quit
        smoking.reminder = nil

        data.habits = [exercise, water, meditation, reading, gym, steps, smoking]

        // История: зарядка до позавчера каждый день, вчера пропуск (карточка «Вернуть серию»).
        for offset in -span ... -2 {
            data.setStatus(.done, habitID: exercise.id, day: DayKey.make(day(offset)))
        }
        for offset in -span ... -1 where offset % 4 != 0 {
            data.setStatus(.done, habitID: water.id, day: DayKey.make(day(offset)))
            data.setStatus(.done, habitID: steps.id, day: DayKey.make(day(offset)))
        }
        for offset in -span ... -1 where offset % 3 != 0 {
            data.setStatus(.done, habitID: meditation.id, day: DayKey.make(day(offset)))
            if reading.isScheduled(on: day(offset)) {
                data.setStatus(.done, habitID: reading.id, day: DayKey.make(day(offset)))
            }
        }
        for offset in stride(from: -span + 1, through: -1, by: 2) {
            data.setStatus(.done, habitID: gym.id, day: DayKey.make(day(offset)))
        }
        // Сегодня уже кое-что сделано.
        data.setStatus(.done, habitID: steps.id, day: DayKey.make(today))
        if TestMode.has("-design") {
            DesignGallery.enrich(&data, day: day, start: start, ru: ru)
        }
        return data
    }
}

/// Сторож главного потока: замечает подвисания интерфейса и показывает самое долгое
/// в невидимом элементе с id "uitest.hangs", который читает тест.
@MainActor
@Observable
final class HangWatchdog {
    static let shared = HangWatchdog()

    /// Самое долгое подвисание, мс, и сколько было подвисаний дольше 250 мс.
    private(set) var worstMs = 0
    private(set) var count = 0

    private init() {}

    nonisolated func start() {
        let thread = Thread {
            // Первые секунды идёт запуск: его меряет тест отдельно.
            Thread.sleep(forTimeInterval: 3)
            while true {
                let sent = Date()
                let semaphore = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { semaphore.signal() }
                semaphore.wait()
                let ms = Int(Date().timeIntervalSince(sent) * 1000)
                if ms > 250 {
                    Task { @MainActor in
                        HangWatchdog.shared.record(ms)
                    }
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    private func record(_ ms: Int) {
        count += 1
        worstMs = max(worstMs, ms)
    }
}

/// Невидимая метка для теста: "<самое долгое подвисание, мс>/<сколько раз>".
struct HangReport: View {
    @State private var watchdog = HangWatchdog.shared

    var body: some View {
        Text(verbatim: "\(watchdog.worstMs)/\(watchdog.count)")
            .font(.system(size: 1))
            .opacity(0.01)
            .frame(width: 1, height: 1)
            .accessibilityIdentifier("uitest.hangs")
            .accessibilityLabel(Text(verbatim: "\(watchdog.worstMs)/\(watchdog.count)"))
            .allowsHitTesting(false)
    }
}
#endif
