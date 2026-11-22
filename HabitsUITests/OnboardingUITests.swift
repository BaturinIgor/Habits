import XCTest

/// Онбординг 1.7 (KAN-121, KAN-122, KAN-169): цель → привычки → итог → пейволл → «Сегодня».
@MainActor
final class OnboardingUITests: XCTestCase {
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Полный путь новой бесплатной установки: «Продолжить бесплатно» на пейволле видна сразу,
    /// а после неё на «Сегодня» созданные привычки и подсказка первой отметки.
    func testGoalFlowEndsOnTodayWithHabits() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-uitest-onboarding", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(element(app, "screen.onboarding").waitForExistence(timeout: 20))
        let next = element(app, "onboarding.next")
        XCTAssertFalse(next.isEnabled, "Continue is disabled until a goal is chosen")
        element(app, "onboarding.goal.energy").tap()
        XCTAssertTrue(next.isEnabled)
        next.tap()

        // Привычки программы с галочками.
        XCTAssertTrue(app.buttons["Drink water"].waitForExistence(timeout: 5))
        next.tap()

        // Итог и «Начать».
        XCTAssertTrue(app.staticTexts["Your plan is ready"].waitForExistence(timeout: 5))
        next.tap()

        // Пейволл: кнопка видна сразу, без ожидания (правило App Store 3.1.2).
        let free = element(app, "paywall.continueFree")
        XCTAssertTrue(free.waitForExistence(timeout: 2))
        XCTAssertTrue(free.isHittable)
        free.tap()

        // «Сегодня» с привычками программы и подсказкой первого дня.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "today.firstDay.hint").waitForExistence(timeout: 5))
        // Карточки созданных привычек (список ленивый: нижние могут быть ещё не построены).
        let toggles = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "habit.toggle."))
        XCTAssertGreaterThan(toggles.count, 0)
    }

    /// Пропуск: сразу «Сегодня», без пейволла.
    func testSkipGoesStraightToToday() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-uitest-onboarding", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(element(app, "screen.onboarding").waitForExistence(timeout: 20))
        element(app, "onboarding.skip").tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(element(app, "paywall.continueFree").exists)
        XCTAssertFalse(element(app, "today.firstDay.hint").exists)
    }

    /// Обновление со старой версии (demo-данные: онбординг уже пройден): ни онбординга, ни пейволла.
    func testUpdateShowsNeitherOnboardingNorPaywall() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-uitest-free", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        sleep(2)
        XCTAssertFalse(element(app, "screen.onboarding").exists)
        XCTAssertFalse(element(app, "paywall.continueFree").exists)
        XCTAssertFalse(element(app, "today.firstDay.hint").exists)
    }
}
