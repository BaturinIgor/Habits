import XCTest

/// Прогон по всем основным экранам на демо-данных:
/// - элементы интерфейса не наезжают друг на друга (обычный и крупный шрифт, английский и русский);
/// - переходы между экранами быстрые, главный поток не подвисает;
/// - снимки всех экранов сохраняются (вложения в отчёте и папка SCREENSHOTS_DIR в CI).
@MainActor
final class ScreensUITests: XCTestCase {
    private var issues: [String] = []
    private var timings: [String] = []
    private var shotIndex = 0
    private var runName = ""
    private var slowSteps: [(what: String, seconds: TimeInterval)] = []
    /// Медленные шаги всех прогонов (английский и русский идут в одном процессе тестов).
    private static var slowEverywhere: [String: [String]] = [:]

    /// Пределы ловят зависания, а не обычную медлительность: симулятор в CI в разы медленнее
    /// телефона, а каждый запрос теста к интерфейсу сам занимает главный поток приложения.
    /// Скорость расчётов отдельно и точнее проверяет PerformanceTests.
    private let stepLimit: TimeInterval = 10

    private static func habitID(_ n: Int) -> String {
        String(format: "00000000-0000-0000-0000-%012d", n)
    }

    private func begin(_ name: String) {
        continueAfterFailure = true
        runName = name
        issues = []
        timings = []
        slowSteps = []
        shotIndex = 0
    }

    // MARK: Тесты

    func testAllScreensEnglish() {
        begin("en")
        let app = launch(["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        tour(app)
        finish(app)
    }

    func testAllScreensRussianLargeText() {
        begin("ru-large")
        let app = launch([
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL",
        ])
        tour(app)
        finish(app)
    }

    func testWhatsNewAndOnboarding() {
        begin("intro")
        let app = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-uitest-whatsnew"])
        let whatsNew = element(app, "screen.whatsnew")
        if wait(whatsNew, "What's New sheet", timeout: 6) {
            check(app, "whatsnew", in: whatsNew)
            app.swipeUp()
            check(app, "whatsnew-bottom", in: whatsNew)
            tap(app, element(app, "sheet.close"), "close What's New")
        }
        app.terminate()

        let fresh = launch(["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-uitest-onboarding"])
        let onboarding = element(fresh, "screen.onboarding")
        if wait(onboarding, "onboarding", timeout: 6) {
            check(fresh, "onboarding", in: onboarding)
        }
        finish(fresh)
    }

    // MARK: Маршрут по экранам

    private func tour(_ app: XCUIApplication) {
        let exercise = Self.habitID(1)
        let water = Self.habitID(2)
        let meditation = Self.habitID(3)
        let smoking = Self.habitID(7)

        // «Сегодня»
        check(app, "today")
        app.swipeUp()
        check(app, "today-scrolled")
        scrollToTop(app)

        // Отметки: количественная и обычная привычка.
        tap(app, reveal(app, element(app, "habit.toggle.\(water)")), "tap water")
        tap(app, reveal(app, element(app, "habit.toggle.\(exercise)")), "check off exercise")
        sleep(2)
        check(app, "today-after-checks")

        // Таймер
        tap(app, reveal(app, element(app, "habit.toggle.\(meditation)")), "open timer")
        let timer = element(app, "screen.timer")
        if wait(timer, "timer sheet") {
            check(app, "timer", in: timer)
            tap(app, element(app, "timer.start"), "start timer", expect: element(app, "timer.stop"))
            sleep(2)
            check(app, "timer-running", in: timer)
            tap(app, element(app, "timer.stop"), "stop timer", expect: element(app, "timer.start"))
            tap(app, element(app, "sheet.close"), "close timer")
        }
        scrollToTop(app)

        // Экран привычки и редактор
        tap(app, reveal(app, element(app, "habit.open.\(exercise)")), "open habit", expect: element(app, "detail.edit"))
        check(app, "detail")
        app.swipeUp()
        check(app, "detail-scrolled")
        tap(app, element(app, "detail.edit"), "open editor")
        let editor = element(app, "screen.editor")
        if wait(editor, "editor") {
            check(app, "editor", in: editor)
            for page in 1...3 {
                editor.swipeUp()
                check(app, "editor-\(page)", in: editor)
            }
            tap(app, element(app, "editor.cancel"), "close editor")
        }
        goBack(app)
        scrollToTop(app)

        // «Бросаю»
        let quit = reveal(app, element(app, "quit.open.\(smoking)"))
        tap(app, quit, "open quit habit", expect: app.navigationBars.buttons.firstMatch)
        check(app, "quit-detail")
        goBack(app)
        scrollToTop(app)

        // Каталог
        tap(app, element(app, "today.add"), "open catalog")
        let catalog = element(app, "screen.catalog")
        if wait(catalog, "catalog") {
            check(app, "catalog", in: catalog)
            catalog.swipeUp()
            check(app, "catalog-scrolled", in: catalog)
            tap(app, element(app, "sheet.close"), "close catalog")
        }

        // Остальные вкладки
        tap(app, tab(app, 1), "tab Habits")
        check(app, "habits")
        app.swipeUp()
        check(app, "habits-scrolled")

        tap(app, tab(app, 2), "tab Statistics", expect: element(app, "stats.recap"))
        check(app, "stats")
        tap(app, element(app, "stats.recap"), "open week in review")
        let recap = element(app, "screen.recap")
        if wait(recap, "week in review") {
            check(app, "recap", in: recap)
            tap(app, element(app, "sheet.close"), "close week in review")
        }
        app.swipeUp()
        check(app, "stats-scrolled")
        app.swipeUp()
        check(app, "stats-bottom")

        tap(app, tab(app, 3), "tab Settings")
        check(app, "settings")
        app.swipeUp()
        check(app, "settings-scrolled")
        app.swipeUp()
        check(app, "settings-bottom")

        tap(app, tab(app, 0), "tab Today")
        check(app, "today-again")
    }

    // MARK: Запуск и итог

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"] + arguments
        let start = Date()
        app.launch()
        // Приложение готово, когда видна панель вкладок или первый экран.
        let ready = app.tabBars.firstMatch.waitForExistence(timeout: 20)
            || element(app, "screen.onboarding").exists
            || element(app, "screen.whatsnew").exists
        let elapsed = Date().timeIntervalSince(start)
        timings.append(String(format: "%@ launch (info, cold CI simulator): %.2f s", runName, elapsed))
        // Время запуска только для сведения: первый запуск на холодном симуляторе CI
        // включает установку и загрузку системы и бывает 15–45 с, к телефону это не относится.
        if !ready {
            issues.append("\(runName): the app did not show its first screen in 20 s")
        }
        return app
    }

    private func finish(_ app: XCUIApplication) {
        let hangs = element(app, "uitest.hangs")
        if hangs.exists {
            let parts = hangs.label.split(separator: "/").compactMap { Int($0) }
            if parts.count == 2 {
                // Только для сведения: сюда попадают и паузы от самих запросов теста к интерфейсу.
                timings.append("\(runName) main thread (info, includes test queries): worst stall \(parts[0]) ms, stalls over 250 ms: \(parts[1])")
            }
        }
        // Симулятор CI иногда замирает на десятки секунд целиком (видно по тому, что тот же шаг
        // в другом прогоне занимает 1–2 с). Поэтому одиночный медленный шаг — предупреждение,
        // а ошибка — если шаг медленный в двух прогонах подряд: так ведёт себя настоящее зависание.
        var warnings: [String] = []
        for step in slowSteps {
            let text = String(format: "%@: %@ took %.1f s (limit %.0f s)", runName, step.what, step.seconds, stepLimit)
            if let earlier = Self.slowEverywhere[step.what], !earlier.isEmpty {
                issues.append(text + ", also slow in " + earlier.joined(separator: ", "))
            } else {
                warnings.append(text + " (once, CI simulator stall?)")
            }
            Self.slowEverywhere[step.what, default: []].append(runName)
        }
        let report = (["Timings:"] + timings + ["", "Warnings:"] + (warnings.isEmpty ? ["none"] : warnings) + ["", "Problems:"] + (issues.isEmpty ? ["none"] : issues))
            .joined(separator: "\n")
        print("==== UI REPORT \(runName) ====\n\(report)\n==== END UI REPORT ====")
        let attachment = XCTAttachment(string: report)
        attachment.name = "report-\(runName)"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = Self.screenshotsDir {
            try? report.write(to: dir.appendingPathComponent("report-\(runName).txt"), atomically: true, encoding: .utf8)
        }
        for issue in issues {
            XCTFail(issue)
        }
    }

    // MARK: Действия

    /// Кнопка вкладки. На iOS 26 панель сворачивается при прокрутке вниз и показывает
    /// только текущую вкладку, поэтому сначала прокручиваем чуть вверх, чтобы она развернулась.
    private func tab(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        let buttons = app.tabBars.firstMatch.buttons
        for _ in 0..<3 where buttons.count < 4 {
            app.swipeDown()
        }
        return buttons.element(boundBy: index)
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    private func wait(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 6) -> Bool {
        if element.waitForExistence(timeout: timeout) { return true }
        issues.append("\(runName): \(what) did not appear")
        return false
    }

    /// Нажатие с замером: сколько прошло до появления ожидаемого элемента.
    private func tap(_ app: XCUIApplication, _ target: XCUIElement, _ what: String, expect: XCUIElement? = nil) {
        guard target.waitForExistence(timeout: 6) else {
            issues.append("\(runName): can't \(what), the control was not found")
            return
        }
        let start = Date()
        target.tap()
        if let expect {
            guard expect.waitForExistence(timeout: 10) else {
                issues.append("\(runName): \(what) did not respond in 10 s")
                return
            }
        }
        let elapsed = Date().timeIntervalSince(start)
        timings.append(String(format: "%@ %@: %.2f s", runName, what, elapsed))
        if elapsed > stepLimit {
            slowSteps.append((what: what, seconds: elapsed))
        }
    }

    /// Прокручивает «Сегодня», пока элемент не станет доступен для нажатия.
    private func reveal(_ app: XCUIApplication, _ target: XCUIElement) -> XCUIElement {
        if target.exists && target.isHittable { return target }
        scrollToTop(app)
        for _ in 0..<8 {
            if target.exists && target.isHittable { return target }
            app.swipeUp()
        }
        return target
    }

    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<4 { app.swipeDown() }
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 4) { back.tap() }
    }

    // MARK: Проверка раскладки

    private static var screenshotsDir: URL? {
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private struct Item {
        let type: XCUIElement.ElementType
        let label: String
        let frame: CGRect
    }

    private static let checkedTypes: Set<XCUIElement.ElementType> = [
        .staticText, .button, .switch, .textField, .secureTextField, .link, .slider, .stepper, .segmentedControl,
    ]
    private static let barTypes: Set<XCUIElement.ElementType> = [
        .navigationBar, .tabBar, .toolbar, .keyboard, .statusBar,
    ]

    /// Снимок экрана и поиск наездов: два элемента пересекаются заметно, но ни один не внутри другого.
    private func check(_ app: XCUIApplication, _ name: String, in root: XCUIElement? = nil) {
        // Даём анимациям закончиться.
        usleep(600_000)
        shotIndex += 1
        let fileName = String(format: "%@-%02d-%@", runName, shotIndex, name)
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = Self.screenshotsDir {
            try? shot.pngRepresentation.write(to: dir.appendingPathComponent(fileName + ".png"))
        }

        guard let full = try? app.snapshot() else {
            issues.append("\(runName) \(name): could not read the screen")
            return
        }
        let screen = app.windows.firstMatch.frame
        var bars: [CGRect] = []
        collectBars(full, into: &bars)
        // Верхний край содержимого: под ним закрепляются заголовки разделов списка
        // («Утро», «Вечер»), и строки при прокрутке законно уезжают под них.
        let contentTop = bars.filter { $0.minY < screen.height / 3 }.map(\.maxY).max() ?? screen.minY

        let scope: XCUIElementSnapshot
        if let root, let snap = try? root.snapshot() {
            scope = snap
        } else {
            scope = full
        }
        var items: [Item] = []
        collect(scope, into: &items)
        items = items.filter { item in
            let f = item.frame
            guard f.width >= 3, f.height >= 3, screen.insetBy(dx: -1, dy: -1).contains(f) else { return false }
            return !bars.contains { $0.intersects(f.insetBy(dx: 1, dy: 1)) }
        }

        var found = Set<String>()
        for i in items.indices {
            for j in items.indices where j > i {
                let a = items[i].frame, b = items[j].frame
                if min(a.minY, b.minY) <= contentTop + 3 { continue }
                if a.insetBy(dx: -1.5, dy: -1.5).contains(b) || b.insetBy(dx: -1.5, dy: -1.5).contains(a) { continue }
                let overlap = a.intersection(b)
                guard !overlap.isNull, overlap.width > 3, overlap.height > 3 else { continue }
                let smaller = min(a.width * a.height, b.width * b.height)
                guard overlap.width * overlap.height > smaller * 0.2 else { continue }
                let text = "\(runName) \(name): “\(items[i].label)” overlaps “\(items[j].label)” (screenshot \(fileName))"
                if found.insert(text).inserted {
                    issues.append(text)
                }
            }
        }
    }

    private func collectBars(_ snap: XCUIElementSnapshot, into bars: inout [CGRect]) {
        if Self.barTypes.contains(snap.elementType) {
            bars.append(snap.frame)
            return
        }
        for child in snap.children {
            collectBars(child, into: &bars)
        }
    }

    /// clip — видимая область ближайшего ScrollView: то, что прокручено за его край (например, под кнопку
    /// внизу экрана онбординга), обрезано и наездом не считается.
    private func collect(_ snap: XCUIElementSnapshot, into items: inout [Item], clip: CGRect = .infinite) {
        if Self.barTypes.contains(snap.elementType) { return }
        if snap.identifier == "uitest.hangs" { return }
        var clip = clip
        if snap.elementType == .scrollView { clip = clip.intersection(snap.frame) }
        if Self.checkedTypes.contains(snap.elementType) {
            let label = snap.label.isEmpty ? (snap.identifier.isEmpty ? "\(snap.elementType)" : snap.identifier) : snap.label
            let visible = snap.frame.intersection(clip)
            if !visible.isNull {
                items.append(Item(type: snap.elementType, label: String(label.prefix(60)), frame: visible))
            }
        }
        for child in snap.children {
            collect(child, into: &items, clip: clip)
        }
    }
}
