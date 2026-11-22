import FirebaseAnalytics
import FirebaseCore
import Foundation
import SwiftUI
import UIKit

/// Анонимная статистика через Google Analytics for Firebase.
///
/// - Экраны уходят как `screen_view`, из них Firebase сам считает время на экранах, сессии и переходы.
/// - Каждое действие, нажатие и свайп уходит своим событием (`habit_check`, `gesture` и т. д.):
///   у Firebase нет лимита на число событий, а отправляет он их пачками сам.
/// - Раз в день уходит `daily_state`: числа и флаги о состоянии приложения.
///
/// Личные данные не отправляются никогда: ни названий привычек, ни заметок, ни текста настроения.
/// Все имена событий и параметров берутся только из перечислений в AnalyticsCatalog.swift.
/// IDFA не собирается (AdSupport не подключён, окна ATT нет), IDFV и рекламные сигналы выключены в Info.plist.
/// Без GoogleService-Info.plist (сборка для SideStore, локальная сборка) и в автотестах ничего не отправляется.
@MainActor
final class Analytics {
    static let shared = Analytics()

    /// Выключатель в настройках. Хранится только на устройстве: true - выключено, false - включено, нет значения -
    /// пользователь ещё не выбирал (тогда действует enabledByDefault).
    nonisolated static let optOutKey = "analyticsOptOut"

    /// Собирать ли статистику, пока пользователь не трогал выключатель. Сейчас: да, пока не выключит (opt-out).
    /// Чтобы перейти на явное согласие (opt-in), достаточно поменять на false: в Info.plist
    /// FIREBASE_ANALYTICS_COLLECTION_ENABLED = false, поэтому Firebase сам ничего не собирает, пока код не включит сбор.
    nonisolated static let enabledByDefault = true

    private let defaults = UserDefaults.standard
    private var configured = false
    private var screenStack: [AnalyticsScreen] = []

    /// daily_state уже считается в фоне: не запускаем второй расчёт при быстрых повторных активациях.
    private var stateInFlight = false

    private enum Key {
        static let stateDay = "analytics.stateDay"
        static let installSent = "analytics.installSent"
        /// Первый запуск версии со статистикой (1.6+), а не установка: у обновившихся это день обновления.
        static let firstSeen = "analytics.firstLaunch"
    }

    private init() {}

    /// Firebase настроен (есть GoogleService-Info.plist), это не автотест и не отладочная сборка.
    /// В отладочной сборке статистику можно включить аргументом запуска -AnalyticsDebug (вместе с -FIRDebugEnabled
    /// события видны в Firebase DebugView).
    static var isAvailable: Bool {
        guard !TestMode.isUITest, !isRunningTests,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return false }
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-AnalyticsDebug")
        #else
        return true
        #endif
    }

    /// Юнит-тесты запускают приложение как хост: там статистика не нужна даже с GoogleService-Info.plist.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
    }

    /// Включена ли статистика пользователем (или по умолчанию, если он не выбирал).
    nonisolated static func isUserEnabled(_ defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: optOutKey) as? Bool).map { !$0 } ?? enabledByDefault
    }

    /// Работает ли отправка: Firebase настроен и пользователь не выключил статистику.
    var isActive: Bool { configured && Self.isUserEnabled(defaults) }

    /// Вызывается при запуске приложения.
    func start() {
        guard Self.isAvailable, !configured,
              let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              // Испорченный plist: FirebaseApp.configure() уронил бы приложение, а так просто нет статистики.
              let options = FirebaseOptions(contentsOfFile: path) else { return }
        FirebaseApp.configure(options: options)
        configured = true
        if defaults.object(forKey: Key.firstSeen) == nil {
            defaults.set(Date(), forKey: Key.firstSeen)
        }
        // В Info.plist сбор выключен (FIREBASE_ANALYTICS_COLLECTION_ENABLED = false): включаем только здесь.
        let enabled = Self.isUserEnabled(defaults)
        FirebaseAnalytics.Analytics.setAnalyticsCollectionEnabled(enabled)
        if enabled { setUserProperties() }
    }

    /// Свойства пользователя для когорт. resetAnalyticsData() их стирает, поэтому ставим и при повторном включении.
    private func setUserProperties() {
        if let first = defaults.object(forKey: Key.firstSeen) as? Date {
            FirebaseAnalytics.Analytics.setUserProperty(Self.weekKey(first), forName: "first_seen_week")
        }
        FirebaseAnalytics.Analytics.setUserProperty(HabitStore.shared.data.isPro ? "1" : "0", forName: "is_pro")
    }

    // MARK: Жизненный цикл

    /// Приложение стало активным: событие установки (один раз) и состояние (раз в день).
    func appBecameActive() {
        guard isActive else { return }
        // Без Firebase или после выключения в настройках жесты даже не наблюдаем.
        AnalyticsGestures.attachToWindows()
        if !defaults.bool(forKey: Key.installSent) {
            defaults.set(true, forKey: Key.installSent)
            send(.appInstalled(isUpdate: HabitStore.shared.data.settings.onboardingDone))
        }
        let data = HabitStore.shared.data
        FirebaseAnalytics.Analytics.setUserProperty(data.isPro ? "1" : "0", forName: "is_pro")
        let today = DayKey.make(Date())
        if defaults.string(forKey: Key.stateDay) != today, !stateInFlight {
            stateInFlight = true
            let daysSinceFirstSeen = (defaults.object(forKey: Key.firstSeen) as? Date).map {
                max(0, Calendar.app.dateComponents([.day], from: $0, to: Date()).day ?? 0)
            }
            // Снимок проходит по всем отметкам (на больших данных это сотни мс): считаем не на главном потоке,
            // чтобы не тормозить запуск.
            Task.detached(priority: .utility) {
                var payload = AnalyticsSnapshot.make(data)
                if let daysSinceFirstSeen { payload["User.daysSinceFirstSeen"] = daysSinceFirstSeen }
                let parameters = Self.firebaseParameters(payload)
                await MainActor.run {
                    let analytics = Analytics.shared
                    analytics.stateInFlight = false
                    guard analytics.isActive else { return }
                    FirebaseAnalytics.Analytics.logEvent("daily_state", parameters: parameters)
                    // День отмечаем только после отправки: если статистику выключили на время расчёта, отправим позже.
                    analytics.defaults.set(today, forKey: Key.stateDay)
                }
            }
        }
    }

    /// Пользователь выключил или включил статистику в настройках.
    func setEnabled(_ enabled: Bool) {
        defaults.set(!enabled, forKey: Self.optOutKey)
        guard configured else { return }
        FirebaseAnalytics.Analytics.setAnalyticsCollectionEnabled(enabled)
        if enabled {
            // Включили посреди сессии: жесты и свойства пользователя сразу, не дожидаясь следующего запуска.
            setUserProperties()
            AnalyticsGestures.attachToWindows()
        } else {
            FirebaseAnalytics.Analytics.resetAnalyticsData()
        }
    }

    // MARK: Экраны, действия, жесты

    func screenAppeared(_ screen: AnalyticsScreen) {
        screenStack.removeAll { $0 == screen }
        screenStack.append(screen)
        logScreen(screen)
    }

    func screenDisappeared(_ screen: AnalyticsScreen) {
        let wasTop = screenStack.last == screen
        screenStack.removeAll { $0 == screen }
        // Закрыли лист или вернулись назад: снова показан экран под ним.
        if wasTop, let top = screenStack.last { logScreen(top) }
    }

    /// Экран, на котором сейчас пользователь.
    var currentScreen: AnalyticsScreen? { screenStack.last }

    /// Действие пользователя: кнопка, переключатель, отметка привычки.
    func action(_ action: AnalyticsAction) {
        log(action.rawValue, ["screen": currentScreen?.rawValue ?? "Other"])
    }

    /// Нажатие или жест на текущем экране (считает AnalyticsGestures).
    func gesture(_ kind: AnalyticsGestures.Kind) {
        log("gesture", ["screen": currentScreen?.rawValue ?? "Other", "kind": kind.rawValue])
    }

    /// Редкое важное событие (покупка, пейвол, новая привычка...).
    func send(_ event: AnalyticsEvent) {
        var payload = event.payload
        if let value = event.floatValue { payload["value"] = value }
        payload["screen"] = currentScreen?.rawValue ?? "Other"
        log(event.type, payload)
    }

    /// Показан шаг онбординга: событие onboarding_step с параметром step (1.7, KAN-168).
    func onboardingStep(_ step: Int) {
        send(.onboardingStep(step: step))
    }

    // MARK: Отправка

    private func logScreen(_ screen: AnalyticsScreen) {
        guard isActive else { return }
        FirebaseAnalytics.Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: screen.rawValue,
            AnalyticsParameterScreenClass: screen.rawValue,
        ])
    }

    private func log(_ name: String, _ payload: [String: Any]) {
        guard isActive else { return }
        FirebaseAnalytics.Analytics.logEvent(Self.firebaseName(name), parameters: Self.firebaseParameters(payload))
    }

    /// "Habit.hasReminder" -> "habit_has_reminder": Firebase разрешает только буквы, цифры и _, до 40 символов.
    nonisolated static func firebaseName(_ name: String) -> String {
        var result = ""
        var previous: Character = "_"
        for char in name {
            defer { previous = char }
            if char == "." || char == "-" || char == " " {
                if !result.hasSuffix("_") { result.append("_") }
            } else if char.isUppercase {
                // Подчёркивание только на границе слова: exportCSV -> export_csv.
                if !result.isEmpty && !result.hasSuffix("_") && (previous.isLowercase || previous.isNumber) { result.append("_") }
                result.append(contentsOf: char.lowercased())
            } else if char.isLetter || char.isNumber || char == "_" {
                result.append(char)
            }
        }
        return String(result.prefix(40))
    }

    /// Параметры для Firebase: не больше 25, строки до 100 символов, флаги как 0/1.
    nonisolated static func firebaseParameters(_ payload: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in payload.sorted(by: { $0.key < $1.key }).prefix(25) {
            let name = firebaseName(key)
            switch value {
            case let flag as Bool: result[name] = flag ? 1 : 0
            case let number as Int: result[name] = number
            case let number as Double: result[name] = number
            case let text as String: result[name] = String(text.prefix(100))
            // Другие типы не отправляем: их текстовое описание могло бы унести лишнее.
            default: continue
            }
        }
        return result
    }

    /// Неделя установки вида 2026-W47: для когорт удержания.
    private static func weekKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }
}

// MARK: - Отметка экрана

extension View {
    /// Отмечает показ экрана (screen_view): из этого Firebase считает время на экранах и переходы.
    func analyticsScreen(_ screen: AnalyticsScreen) -> some View {
        onAppear { Analytics.shared.screenAppeared(screen) }
            .onDisappear { Analytics.shared.screenDisappeared(screen) }
    }

    /// Считает нажатие на элемент без своего действия (например, ShareLink).
    func analyticsTap(_ action: AnalyticsAction) -> some View {
        simultaneousGesture(TapGesture().onEnded { Analytics.shared.action(action) })
    }
}

// MARK: - Жесты

/// Считает все нажатия, долгие нажатия и свайпы в окне приложения.
/// Распознаватель только наблюдает: он всегда завершается неудачей и не мешает кнопкам и прокрутке.
enum AnalyticsGestures {
    enum Kind: String {
        case tap, longPress, swipeLeft, swipeRight, swipeUp, swipeDown
    }

    @MainActor private static var attached = Set<ObjectIdentifier>()

    @MainActor
    static func attachToWindows() {
        guard !TestMode.isUITest else { return }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            // Только обычные окна приложения: клавиатура и системные окна не считаются.
            for window in windowScene.windows where window.windowLevel == .normal && !attached.contains(ObjectIdentifier(window)) {
                attached.insert(ObjectIdentifier(window))
                let observer = Observer(target: nil, action: nil)
                observer.cancelsTouchesInView = false
                observer.delaysTouchesBegan = false
                observer.delaysTouchesEnded = false
                observer.delegate = observer
                window.addGestureRecognizer(observer)
            }
        }
    }

    private final class Observer: UIGestureRecognizer, UIGestureRecognizerDelegate {
        private var start: CGPoint = .zero
        private var startTime: TimeInterval = 0

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            guard let touch = touches.first, event.allTouches?.count == 1 else {
                state = .failed
                return
            }
            start = touch.location(in: view)
            startTime = touch.timestamp
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            finish(touches)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            finish(touches)
        }

        private func finish(_ touches: Set<UITouch>) {
            defer { state = .failed }
            guard let touch = touches.first else { return }
            let end = touch.location(in: view)
            let dx = end.x - start.x, dy = end.y - start.y
            let distance = (dx * dx + dy * dy).squareRoot()
            let kind: Kind
            if distance < 12 {
                kind = touch.timestamp - startTime >= 0.5 ? .longPress : .tap
            } else if distance >= 40 {
                kind = abs(dx) > abs(dy) ? (dx > 0 ? .swipeRight : .swipeLeft) : (dy > 0 ? .swipeDown : .swipeUp)
            } else {
                return
            }
            Analytics.shared.gesture(kind)
        }

        override func reset() {
            super.reset()
            start = .zero
            startTime = 0
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
