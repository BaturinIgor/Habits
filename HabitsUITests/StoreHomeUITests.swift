import XCTest

/// Скриншот App Store 06 (виджеты на экране Домой, KAN-236).
/// Язык кадра — язык системы симулятора: экран Домой и виджеты берут его.
/// Кадр 04 (уведомление) так не снять: симулятор iOS 27.2 не показывает баннеры ни от `simctl push`,
/// ни от локальных уведомлений, поэтому в наборах 1.7.2 его нет.
/// Запускается только с STORE_HOME_DIR, в обычном прогоне тестов пропускается.
///
/// STORE_HOME_STEP=setup — один раз добавить виджеты ZenHab (средний и маленький) на первый экран.
/// STORE_HOME_STEP=shoot — снять 06-widgets.png.
@MainActor
final class StoreHomeUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private var dir: URL? {
        guard let path = ProcessInfo.processInfo.environment["STORE_HOME_DIR"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var step: String { ProcessInfo.processInfo.environment["STORE_HOME_STEP"] ?? "shoot" }

    func testHome() throws {
        guard let dir else { throw XCTSkip("STORE_HOME_DIR is not set: App Store home screen shots only") }
        continueAfterFailure = true
        // Демо-данные пишутся в общую с виджетами папку при запуске приложения.
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-design", "-design-store"]
        app.launch()
        allowAlerts()
        sleep(1)
        XCUIDevice.shared.press(.home)
        sleep(1)
        // Второе нажатие возвращает на первую страницу экрана Домой, где стоят виджеты.
        XCUIDevice.shared.press(.home)
        sleep(2)
        if step == "setup" {
            try addWidgets(dir)
        } else {
            try shoot(dir)
        }
    }

    private func save(_ name: String, _ dir: URL) {
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent(name))
    }

    private func dump(_ name: String, _ dir: URL) {
        try? springboard.debugDescription.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func allowAlerts() {
        for _ in 0..<3 {
            for target in [springboard, XCUIApplication()] {
                let alert = target.alerts.firstMatch
                guard alert.waitForExistence(timeout: 2) else { continue }
                alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
                sleep(1)
            }
        }
    }

    private func shoot(_ dir: URL) throws {
        // Системные виджеты (Карты, Календарь) после смены языка перерисовываются не сразу.
        sleep(8)
        save("06-widgets.png", dir)
    }

    /// Правка экрана Домой: «Изменить» -> «Добавить виджет» -> ZenHab -> размер -> «Добавить».
    /// Подписи кнопок английские: настраивать при английском языке системы.
    private func addWidgets(_ dir: URL) throws {
        // Сначала маленький, потом средний: новый виджет встаёт в начало экрана, и средний окажется сверху.
        for (index, swipes) in [0, 1].enumerated() {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).press(forDuration: 1.5)
            sleep(1)
            dump("setup-\(index)-1-edit.txt", dir)
            let edit = springboard.buttons["Edit"]
            if edit.waitForExistence(timeout: 3) { edit.tap(); sleep(1) }
            let add = springboard.buttons["Add Widget"]
            guard add.waitForExistence(timeout: 3) else { dump("setup-\(index)-2-no-add.txt", dir); XCTFail("No Add Widget"); return }
            dump("setup-\(index)-2-menu.txt", dir)
            sleep(1)
            add.tap()
            sleep(2)
            let search = springboard.searchFields.firstMatch
            if search.waitForExistence(timeout: 3) {
                search.tap()
                search.typeText("ZenHab")
                sleep(2)
            }
            dump("setup-\(index)-3-gallery.txt", dir)
            let app = springboard.cells["ZenHab"]
            guard app.waitForExistence(timeout: 3) else { XCTFail("No ZenHab in widget gallery"); return }
            app.tap()
            sleep(2)
            for _ in 0..<swipes { springboard.swipeLeft(); sleep(1) }
            dump("setup-\(index)-4-sizes.txt", dir)
            save("setup-\(index)-4-sizes.png", dir)
            let confirm = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Add Widget'")).firstMatch
            guard confirm.waitForExistence(timeout: 3) else { XCTFail("No Add Widget in sizes"); return }
            confirm.tap()
            sleep(2)
            let done = springboard.buttons["Done"]
            if done.waitForExistence(timeout: 3) { done.tap() }
            XCUIDevice.shared.press(.home)
            sleep(2)
            save("setup-\(index)-5-home.png", dir)
        }
        springboard.swipeLeft()
        sleep(1)
        save("setup-9-page2.png", dir)
        springboard.swipeRight()
    }
}
