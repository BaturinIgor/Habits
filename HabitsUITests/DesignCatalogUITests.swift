import XCTest

/// Макеты всех экранов, состояний и попапов: design/<версия>/screens.
/// Каждый снимок — отдельный запуск приложения с `-design-screen` (см. DesignGallery.swift),
/// в светлой и тёмной теме. Запускается только когда задан DESIGN_DIR (workflow Design screens),
/// в обычном прогоне тестов пропускается.
///
/// Какие снимки делать, задаёт DESIGN_SCREENS: имена снимков через запятую (`10-onboarding,36-paywall`, `health-*` — по префиксу)
/// или `all` для полного каталога. Без списка не снимается ничего: макеты версии — только новые
/// и изменённые экраны, остальные берутся из прошлых версий (design/README.md).
@MainActor
final class DesignCatalogUITests: XCTestCase {
    private struct Shot {
        let name: String
        let screen: String
        var alert: String? = nil
        var flags: [String] = []
    }

    private static let shots: [Shot] = [
        // Вкладки
        Shot(name: "01-today", screen: "today"),
        Shot(name: "02-habits", screen: "habits"),
        Shot(name: "03-stats", screen: "stats"),
        Shot(name: "04-settings", screen: "settings"),
        // Пустые состояния
        Shot(name: "05-today-empty", screen: "today", flags: ["-uitest-empty"]),
        Shot(name: "06-habits-empty", screen: "habits", flags: ["-uitest-empty"]),
        Shot(name: "07-stats-empty", screen: "stats", flags: ["-uitest-empty"]),
        // Бесплатная версия (без Pro)
        Shot(name: "08-today-free", screen: "today", flags: ["-uitest-free"]),
        Shot(name: "09-settings-free", screen: "settings", flags: ["-uitest-free"]),
        // Первый запуск и «Что нового»
        Shot(name: "10-onboarding", screen: "today", flags: ["-uitest-onboarding"]),
        Shot(name: "11-whats-new", screen: "whatsNew"),
        // Привычка
        Shot(name: "12-habit-detail", screen: "habitDetail"),
        Shot(name: "13-quit-detail", screen: "quitDetail"),
        Shot(name: "14-quit-relapse-confirm", screen: "quitDetail", alert: "relapse"),
        Shot(name: "15-catalog", screen: "catalog"),
        Shot(name: "16-catalog-free", screen: "catalog", flags: ["-uitest-free"]),
        Shot(name: "17-editor-new", screen: "editorNew"),
        Shot(name: "18-editor-new-free", screen: "editorNew", flags: ["-uitest-free"]),
        Shot(name: "19-editor-edit", screen: "editorEdit"),
        Shot(name: "20-editor-template", screen: "editorTemplate"),
        Shot(name: "21-editor-new-group", screen: "editorEdit", alert: "newGroup"),
        Shot(name: "22-editor-delete-confirm", screen: "editorEdit", alert: "deleteHabit"),
        Shot(name: "23-icon-picker", screen: "iconPicker"),
        Shot(name: "24-voice", screen: "voice"),
        Shot(name: "25-note", screen: "note"),
        Shot(name: "26-timer", screen: "timer"),
        Shot(name: "27-words", screen: "words"),
        // Статистика и настроение
        Shot(name: "28-week-recap", screen: "recap"),
        Shot(name: "29-mood-journal", screen: "moodJournal"),
        Shot(name: "30-mood-journal-free", screen: "moodJournal", flags: ["-uitest-free"]),
        Shot(name: "31-mood-entry", screen: "moodEntry"),
        // Профиль, искры, питомец
        Shot(name: "32-profile", screen: "profile"),
        Shot(name: "33-sparks", screen: "sparks"),
        Shot(name: "34-pet", screen: "pet"),
        Shot(name: "35-pet-rename", screen: "pet", alert: "petRename"),
        // 1.6, KAN-105: своё имя у каждого вида
        Shot(name: "pet-names-01-switched", screen: "petSwitched"),
        Shot(name: "pet-names-02-naming-sheet", screen: "petNaming", flags: ["-design-alert", "petNaming"]),
        Shot(name: "pet-names-03-species-grid", screen: "petSpecies"),
        // Pro
        Shot(name: "36-paywall", screen: "paywall", flags: ["-uitest-free"]),
        Shot(name: "37-paywall-feature", screen: "paywallFeature", flags: ["-uitest-free"]),
        Shot(name: "38-paywall-pro-active", screen: "paywall"),
        // Настройки
        Shot(name: "39-notifications", screen: "notifications"),
        Shot(name: "40-today-screen", screen: "todayScreen"),
        Shot(name: "41-groups", screen: "groups"),
        Shot(name: "42-groups-new", screen: "groups", alert: "groupNew"),
        Shot(name: "43-group-family", screen: "groupDetail"),
        Shot(name: "44-group-family-stop", screen: "groupDetail", alert: "familyEnd"),
        Shot(name: "45-app-icon", screen: "appIcon"),
        Shot(name: "46-app-icon-free", screen: "appIcon", flags: ["-uitest-free"]),
        Shot(name: "47-backup", screen: "backup"),
        Shot(name: "48-backup-restored", screen: "backup", alert: "restored"),
        Shot(name: "49-settings-restart-hint", screen: "settings", alert: "restartHint"),
        // 1.6, App Review 2.5.1: Apple Health в интерфейсе
        Shot(name: "health-01-settings", screen: "settings"),
        Shot(name: "health-02-health-settings", screen: "healthSettings"),
        Shot(name: "health-03-health-settings-free", screen: "healthSettings", flags: ["-uitest-free"]),
        Shot(name: "health-04-editor", screen: "editorHealth"),
        Shot(name: "health-05-editor-free", screen: "editorHealth", flags: ["-uitest-free"]),
        // 1.7, KAN-135: умное время напоминаний
        Shot(name: "smart-01-suggestion", screen: "smartSuggestion"),
        Shot(name: "smart-02-editor-on", screen: "smartEditor"),
        Shot(name: "smart-03-editor-off", screen: "smartEditorOff"),
        // 1.7, KAN-137: инсайты настроения (Pro), мало данных и бесплатная версия
        Shot(name: "insights-01-top", screen: "moodInsights"),
        Shot(name: "insights-02-few-days", screen: "moodInsightsFew"),
        Shot(name: "insights-03-free", screen: "moodInsights", flags: ["-uitest-free"]),
        // Обратная связь
        Shot(name: "50-feedback", screen: "feedback"),
        Shot(name: "51-feedback-send-options", screen: "feedback", alert: "sendOptions"),
        Shot(name: "52-feedback-thanks", screen: "feedback", alert: "thanks"),
        Shot(name: "53-feedback-failed", screen: "feedback", alert: "sendFailed"),
        Shot(name: "54-feedback-no-mail", screen: "feedback", alert: "noMail"),
        Shot(name: "55-feedback-copied", screen: "feedback", alert: "copied"),
        // 1.7, KAN-121/KAN-122/KAN-169: онбординг с целями, пейволл в конце, первый день на «Сегодня»
        Shot(name: "onb-01-goal", screen: "today", flags: ["-uitest-onboarding"]),
        Shot(name: "onb-02-goal-selected", screen: "onboardingGoal", flags: ["-uitest-empty"]),
        Shot(name: "onb-03-habits", screen: "onboardingHabits", flags: ["-uitest-empty"]),
        Shot(name: "onb-04-summary", screen: "onboardingSummary", flags: ["-uitest-empty"]),
        Shot(name: "onb-05-paywall", screen: "onboardingPaywall", flags: ["-uitest-empty", "-uitest-free"]),
        Shot(name: "onb-06-today-first-check", screen: "today", flags: ["-uitest-firstday"]),
        Shot(name: "onb-07-today-celebrate", screen: "today", flags: ["-uitest-firstday-checked"]),
        Shot(name: "onb-08-goal-large", screen: "onboardingGoal", flags: ["-uitest-empty"] + largeText),
        Shot(name: "onb-09-habits-large", screen: "onboardingHabits", flags: ["-uitest-empty"] + largeText),
        Shot(name: "onb-10-today-first-check-large", screen: "today", flags: ["-uitest-firstday"] + largeText),
        Shot(name: "onb-11-today-celebrate-large", screen: "today", flags: ["-uitest-firstday-checked"] + largeText),
        // 1.7, KAN-125: новогоднее предложение (акция включается флагом в любой день)
        Shot(name: "offer-01-today", screen: "today", flags: ["-uitest-free", "-uitest-offer"]),
        Shot(name: "offer-02-settings", screen: "settings", flags: ["-uitest-free", "-uitest-offer"]),
        Shot(name: "offer-03-paywall", screen: "offerPaywall", flags: ["-uitest-free", "-uitest-offer"]),
    ]

    /// Крупный шрифт (Универсальный доступ) для макетов.
    private static let largeText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]

    private static var outputDir: URL? {
        guard let path = ProcessInfo.processInfo.environment["DESIGN_DIR"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testLight() throws {
        try run(dark: false)
    }

    func testDark() throws {
        try run(dark: true)
    }

    /// Снимки из DESIGN_SCREENS. Неизвестные имена — ошибка, чтобы опечатка в screens.txt не прошла молча.
    private static func selectedShots(_ list: String?) -> (shots: [Shot], unknown: [String]) {
        // Строки файла screens.txt: всё после «#» — комментарий; имена через запятую или пробел.
        let names = (list ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .flatMap { line in
                line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first
                    .map { $0.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" }) } ?? []
            }
            .map { String($0) }
        if names == ["all"] { return (shots, []) }
        // «health-*» — все снимки с этим префиксом.
        func matches(_ shot: Shot, _ name: String) -> Bool {
            name.hasSuffix("*") ? shot.name.hasPrefix(String(name.dropLast())) : shot.name == name
        }
        return (shots.filter { shot in names.contains { matches(shot, $0) } },
                names.filter { name in !shots.contains { matches($0, name) } })
    }

    private func run(dark: Bool) throws {
        guard let dir = Self.outputDir else {
            throw XCTSkip("DESIGN_DIR is not set: design screenshots are taken only by the Design screens workflow")
        }
        let selection = Self.selectedShots(ProcessInfo.processInfo.environment["DESIGN_SCREENS"])
        print("==== DESIGN screens: \(selection.shots.map(\.name).joined(separator: ", "))")
        XCTAssertTrue(selection.unknown.isEmpty, "Unknown design screens: \(selection.unknown.joined(separator: ", "))")
        guard !selection.shots.isEmpty else {
            throw XCTSkip("DESIGN_SCREENS is empty: list the new and changed screens in design/<version>/screens.txt or pass all")
        }
        continueAfterFailure = true
        let language = ProcessInfo.processInfo.environment["DESIGN_LANG"] ?? "ru"
        let locale = language == "ru" ? "ru_RU" : "en_US"
        var missing: [String] = []
        for shot in selection.shots {
            let app = XCUIApplication()
            var args = ["-uitest", "-design", "-design-screen", shot.screen,
                        "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
            if dark { args.append("-design-dark") }
            if let alert = shot.alert { args += ["-design-alert", alert] }
            app.launchArguments = args + shot.flags
            app.launch()

            let ready: Bool
            if shot.alert != nil {
                ready = app.alerts.firstMatch.waitForExistence(timeout: 8)
                    || app.sheets.firstMatch.waitForExistence(timeout: 2)
                    || app.buttons["Cancel"].waitForExistence(timeout: 1)
            } else if ["today", "habits", "stats", "settings"].contains(shot.screen) {
                ready = app.tabBars.firstMatch.waitForExistence(timeout: 20)
                    || app.descendants(matching: .any).matching(identifier: "screen.onboarding").firstMatch.exists
            } else {
                ready = app.descendants(matching: .any).matching(identifier: "design.ready").firstMatch.waitForExistence(timeout: 20)
                    || app.descendants(matching: .any).matching(identifier: "screen.onboarding").firstMatch.exists
            }
            if !ready { missing.append(shot.name) }
            // Даём анимациям закончиться.
            sleep(2)
            let theme = dark ? "dark" : "light"
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            if springboard.alerts.firstMatch.exists {
                // Системный запрос доступа (микрофон, распознавание речи) — тоже состояние экрана.
                let file = "\(shot.name)-permission-\(theme).png"
                try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent(file))
                allowSystemAlerts(springboard)
                sleep(2)
            }
            let file = "\(shot.name)-\(theme).png"
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent(file))
            app.terminate()
            // Запрос доступа не должен перейти на следующие снимки.
            allowSystemAlerts(springboard)
        }
        let note = missing.isEmpty ? "all screens shown" : "not confirmed: " + missing.joined(separator: ", ")
        try? note.write(to: dir.appendingPathComponent("report-\(dark ? "dark" : "light").txt"), atomically: true, encoding: .utf8)
        print("==== DESIGN \(dark ? "dark" : "light"): \(note)")
    }

    /// Отвечает «Разрешить» на системные запросы доступа поверх приложения.
    private func allowSystemAlerts(_ springboard: XCUIApplication) {
        for _ in 0..<4 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 1) else { return }
            let button = ["Allow", "OK", "Разрешить"].lazy.map { alert.buttons[$0] }.first { $0.exists }
                ?? alert.buttons.element(boundBy: alert.buttons.count - 1)
            button.tap()
            sleep(1)
        }
    }
}
