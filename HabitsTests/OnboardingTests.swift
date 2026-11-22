import XCTest
@testable import Habits

/// Онбординг 1.7 (KAN-121, KAN-122, KAN-169): программы целей, кому показывать онбординг и пейволл, первый день.
final class OnboardingTests: XCTestCase {
    /// Каждая цель даёт 3–5 привычек из каталога, без повторов, с новыми id.
    func testEveryGoalHasThreeToFiveCatalogHabits() {
        let catalogNames = Set(HabitCatalog.categories(isPro: false).flatMap(\.items).map(\.habit.name))
        for goal in OnboardingGoal.allCases {
            let habits = OnboardingPlan.habits(for: goal, isPro: false)
            XCTAssertEqual(habits.count, goal.itemIDs.count, "\(goal): unknown catalog id")
            XCTAssertTrue((3...5).contains(habits.count), "\(goal)")
            XCTAssertEqual(Set(habits.map(\.name)).count, habits.count, "\(goal)")
            for habit in habits { XCTAssertTrue(catalogNames.contains(habit.name), habit.name) }
            XCTAssertFalse(goal.title.isEmpty)
            XCTAssertFalse(goal.subtitle.isEmpty)
        }
        // Два вызова — разные привычки, а не одни и те же id.
        let first = OnboardingPlan.habits(for: .energy, isPro: false).map(\.id)
        let second = OnboardingPlan.habits(for: .energy, isPro: false).map(\.id)
        XCTAssertTrue(Set(first).isDisjoint(with: second))
    }

    /// Учёба включает изучение слов на предложенном языке.
    func testLearningGoalIncludesWords() {
        let habits = OnboardingPlan.habits(for: .learning, isPro: false)
        XCTAssertEqual(habits.first { $0.isWords }?.wordsLanguage, WordLanguage.suggested)
    }

    /// Выбор программы создаёт ровно отмеченные привычки.
    func testChosenProgramCreatesSelectedHabits() {
        let program = OnboardingPlan.habits(for: .calm, isPro: false)
        let chosen = Array(program.prefix(3))
        let added = OnboardingPlan.habitsToAdd(chosen, to: AppData())
        XCTAssertEqual(added.map(\.id), chosen.map(\.id))
        XCTAssertEqual(added.map(\.name), ["meditate", "breathe", "gratitude"].map { id in
            HabitCatalog.categories(isPro: false).flatMap(\.items).first { $0.id == id }!.habit.name
        })
    }

    /// Повторный показ знакомства не создаёт дубли, бесплатная версия не выходит за лимит.
    func testHabitsToAddSkipsDuplicatesAndRespectsFreeLimit() {
        let program = OnboardingPlan.habits(for: .energy, isPro: false)
        var data = AppData()
        data.settings.proUnlocked = false
        data.habits = [program[0]]
        let added = OnboardingPlan.habitsToAdd(program, to: data)
        XCTAssertEqual(added.count, program.count - 1)
        XCTAssertFalse(added.contains { $0.name == program[0].name })

        data.habits = (0..<4).map { Habit(name: "Old \($0)") }
        XCTAssertEqual(OnboardingPlan.freeSlots(in: data), 1)
        XCTAssertEqual(OnboardingPlan.habitsToAdd(program, to: data).count, 1)

        data.settings.proUnlocked = true
        XCTAssertNil(OnboardingPlan.freeSlots(in: data))
        XCTAssertEqual(OnboardingPlan.habitsToAdd(program, to: data).count, program.count)
    }

    /// Обновление с 1.6: в сохранённых настройках onboardingDone = true и нет новых полей.
    /// Ни онбординг, ни пейволл, ни подсказки первого дня не показываются.
    func testUpdateFromOldVersionSkipsOnboardingAndPaywall() throws {
        let old = #"{"settings":{"onboardingDone":true,"gestureHintShown":true,"whatsNewSeen":"1.6"},"habits":[]}"#
        let data = try JSONDecoder().decode(AppData.self, from: Data(old.utf8))
        XCTAssertFalse(OnboardingPlan.shouldShowOnboarding(data.settings))
        XCTAssertFalse(data.settings.onboardingPaywallSeen)
        XCTAssertFalse(data.settings.firstDayGuide)
        XCTAssertNil(OnboardingPlan.firstDay(data))
        // Пейволл есть только внутри онбординга, а его обновившийся не увидит.
        XCTAssertFalse(OnboardingPlan.shouldShowOnboarding(data.settings) && OnboardingPlan.shouldShowPaywall(data))
    }

    /// Новый пользователь видит онбординг и пейволл один раз; с Pro пейволла нет.
    func testFreshInstallShowsOnboardingAndPaywallOnce() throws {
        var data = AppData()
        data.settings.proUnlocked = false
        XCTAssertTrue(OnboardingPlan.shouldShowOnboarding(data.settings))
        XCTAssertTrue(OnboardingPlan.shouldShowPaywall(data))
        data.settings.onboardingPaywallSeen = true
        XCTAssertFalse(OnboardingPlan.shouldShowPaywall(data))
        // Флаг переживает сохранение.
        let decoded = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        XCTAssertTrue(decoded.settings.onboardingPaywallSeen)

        var pro = AppData()
        pro.settings.proUnlocked = true
        XCTAssertFalse(OnboardingPlan.shouldShowPaywall(pro))
    }

    /// Первый день: подсказка до первой отметки, поздравление после; без привычек и с историей — не начинается.
    func testFirstDayStates() {
        var data = AppData()
        let habit = OnboardingPlan.habits(for: .fitness, isPro: false)[0]
        data.habits = [habit]
        XCTAssertTrue(OnboardingPlan.startsFirstDay(created: 1, data: data))
        XCTAssertFalse(OnboardingPlan.startsFirstDay(created: 0, data: data))
        XCTAssertNil(OnboardingPlan.firstDay(data))

        data.settings.firstDayGuide = true
        XCTAssertEqual(OnboardingPlan.firstDay(data), .hint)
        data.setStatus(.done, habitID: habit.id, day: DayKey.make(Date()))
        XCTAssertEqual(OnboardingPlan.firstDay(data), .celebrate)
        // Повторное знакомство у того, кто уже отмечал: подсказки первого дня не нужны.
        XCTAssertFalse(OnboardingPlan.startsFirstDay(created: 2, data: data))
    }

    /// onboarding_step с параметром step, пропуск и выбор цели — в формате Firebase и без личных данных.
    func testOnboardingAnalyticsNames() {
        XCTAssertEqual(Analytics.firebaseName(AnalyticsEvent.onboardingStep(step: 2).type), "onboarding_step")
        XCTAssertEqual(Analytics.firebaseParameters(AnalyticsEvent.onboardingStep(step: 2).payload)["step"] as? Int, 2)
        XCTAssertEqual(Analytics.firebaseName(AnalyticsEvent.onboardingSkipped(step: 1).type), "onboarding_skipped")
        let goal = Analytics.firebaseParameters(AnalyticsEvent.onboardingGoal(goal: "energy", habits: 4).payload)
        XCTAssertEqual(goal["onboarding_goal"] as? String, "energy")
        XCTAssertEqual(goal["onboarding_habits"] as? Int, 4)
        XCTAssertEqual(OnboardingPlan.Step.allCases.map(\.rawValue), [1, 2, 3, 4])
    }
}
