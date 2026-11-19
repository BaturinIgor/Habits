import XCTest

/// Макеты всех экранов, состояний и попапов: design/<версия>/screens.
/// Каждый снимок — отдельный запуск приложения с `-design-screen` (см. DesignGallery.swift),
/// в светлой и тёмной теме. Запускается только когда задан DESIGN_DIR (workflow Design screens),
/// в обычном прогоне тестов пропускается.
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
        // Привычка
        Shot(name: "12-habit-detail", screen: "habitDetail"),
        Shot(name: "15-catalog", screen: "catalog"),
        Shot(name: "16-catalog-free", screen: "catalog", flags: ["-uitest-free"]),
        Shot(name: "17-editor-new", screen: "editorNew"),
        Shot(name: "18-editor-new-free", screen: "editorNew", flags: ["-uitest-free"]),
        Shot(name: "19-editor-edit", screen: "editorEdit"),
        Shot(name: "20-editor-template", screen: "editorTemplate"),
        Shot(name: "21-editor-new-group", screen: "editorEdit", alert: "newGroup"),
        Shot(name: "22-editor-delete-confirm", screen: "editorEdit", alert: "deleteHabit"),
        Shot(name: "23-icon-picker", screen: "iconPicker"),
        Shot(name: "25-note", screen: "note"),
        Shot(name: "27-words", screen: "words"),
        // Статистика и настроение
        // Профиль, искры, питомец
        Shot(name: "32-profile", screen: "profile"),
        Shot(name: "33-sparks", screen: "sparks"),
        Shot(name: "34-pet", screen: "pet"),
        Shot(name: "35-pet-rename", screen: "pet", alert: "petRename"),
        // Pro
        Shot(name: "36-paywall", screen: "paywall", flags: ["-uitest-free"]),
        Shot(name: "38-paywall-pro-active", screen: "paywall"),
        // Настройки
        Shot(name: "39-notifications", screen: "notifications"),
        Shot(name: "40-today-screen", screen: "todayScreen"),
        Shot(name: "41-groups", screen: "groups"),
        Shot(name: "42-groups-new", screen: "groups", alert: "groupNew"),
        Shot(name: "47-backup", screen: "backup"),
        Shot(name: "49-settings-restart-hint", screen: "settings", alert: "restartHint"),
        // Обратная связь
        Shot(name: "50-feedback", screen: "feedback"),
        Shot(name: "51-feedback-send-options", screen: "feedback", alert: "sendOptions"),
        Shot(name: "52-feedback-thanks", screen: "feedback", alert: "thanks"),
        Shot(name: "53-feedback-failed", screen: "feedback", alert: "sendFailed"),
        Shot(name: "54-feedback-no-mail", screen: "feedback", alert: "noMail"),
        Shot(name: "55-feedback-copied", screen: "feedback", alert: "copied"),
    ]

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

    private func run(dark: Bool) throws {
        guard let dir = Self.outputDir else {
            throw XCTSkip("DESIGN_DIR is not set: design screenshots are taken only by the Design screens workflow")
        }
        continueAfterFailure = true
        let language = ProcessInfo.processInfo.environment["DESIGN_LANG"] ?? "ru"
        let locale = language == "ru" ? "ru_RU" : "en_US"
        var missing: [String] = []
        for shot in Self.shots {
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
