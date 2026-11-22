import FirebaseAnalytics
import FirebaseCore
import Foundation
import StoreKit
import SwiftUI
import UIKit

/// Анонимная статистика через Google Analytics for Firebase.
///
/// - Экраны уходят как `screen_view`, из них Firebase сам считает время на экранах, сессии и переходы.
/// - Каждое действие уходит своим событием (`habit_check` и т. д.): у Firebase нет лимита на число событий,
///   а отправляет он их пачками сам. Нажатия и свайпы только считаются и уходят одним событием `gestures`
///   за заход в приложение (KAN-167): по событию на нажатие забивало топ событий.
/// - user property `build_type` (debug / testflight / appstore): в GA4 отчёты фильтруются по appstore.
/// - Раз в день уходит `daily_state`: числа и флаги о состоянии приложения.
///
/// Личные данные не отправляются никогда: ни названий привычек, ни заметок, ни текста настроения.
/// Все имена событий и параметров берутся только из перечислений в AnalyticsCatalog.swift.
/// IDFA не собирается (AdSupport не подключён, окна ATT нет), IDFV и рекламные сигналы выключены в Info.plist.
/// Без GoogleService-Info.plist (сборка для SideStore, локальная сборка), в автотестах, в Debug и на симуляторе
/// ничего не отправляется.
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

    /// Нажатия и свайпы с последнего входа в приложение: уходят одним событием `gestures` при уходе из него.
    private var gestureCounts: [AnalyticsGestures.Kind: Int] = [:]

    /// Шаги онбординга, уже отправленные за этот запуск: листание назад и вперёд не дублирует шаг.
    private var sentOnboardingSteps = Set<Int>()

    private enum Key {
        static let stateDay = "analytics.stateDay"
        static let installSent = "analytics.installSent"
        /// Первый запуск версии со статистикой (1.6+), а не установка: у обновившихся это день обновления.
        static let firstSeen = "analytics.firstLaunch"
        /// Событие first_check уже ушло (или у пользователя были отметки до 1.7, и первой оно не было бы).
        static let firstCheckDone = "analytics.firstCheckDone"
    }

    private init() {}

    /// Firebase настроен (есть GoogleService-Info.plist), это не автотест, не отладочная сборка и не симулятор.
    /// В отладочной сборке и на симуляторе статистику можно включить аргументом запуска -AnalyticsDebug
    /// (вместе с -FIRDebugEnabled события видны в Firebase DebugView).
    static var isAvailable: Bool {
        guard !TestMode.isUITest, !isRunningTests,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return false }
        return sendsFrom(isDebug: isDebugBuild, isSimulator: isSimulator,
                         forced: ProcessInfo.processInfo.arguments.contains("-AnalyticsDebug"))
    }

    /// Отправлять ли из этой сборки: свои Debug-сборки и симулятор (KAN-167) только по явному -AnalyticsDebug.
    nonisolated static func sendsFrom(isDebug: Bool, isSimulator: Bool, forced: Bool) -> Bool {
        forced || (!isDebug && !isSimulator)
    }

    nonisolated static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    nonisolated static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// Тип сборки для user property `build_type`: по нему в GA4 отсекаются свои устройства.
    enum BuildType: String {
        case debug, testflight, appstore

        /// Debug и симулятор - debug; Release из песочницы App Store (TestFlight, Xcode) - testflight.
        nonisolated static func make(isDebug: Bool, isSimulator: Bool, isSandbox: Bool) -> BuildType {
            if isDebug || isSimulator { return .debug }
            return isSandbox ? .testflight : .appstore
        }
    }

    /// Песочница App Store: TestFlight или установка из Xcode. AppTransaction (iOS 16+) не показывает запросов входа.
    private static func isSandbox() async -> Bool {
        guard let result = try? await AppTransaction.shared else { return false }
        switch result {
        case .verified(let transaction), .unverified(let transaction, _):
            return transaction.environment != .production
        }
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
        // У тех, кто отмечал привычки до 1.7, следующая отметка уже не первая: first_check им не отправляем.
        if !defaults.bool(forKey: Key.firstCheckDone),
           HabitStore.shared.data.checkIns.values.contains(where: { $0.status == .done }) {
            defaults.set(true, forKey: Key.firstCheckDone)
        }
        NotificationPlanner.onPermissionResult = { granted in Analytics.shared.notificationPermission(granted: granted) }
    }

    /// Свойства пользователя для когорт. resetAnalyticsData() их стирает, поэтому ставим и при повторном включении.
    private func setUserProperties() {
        if let first = defaults.object(forKey: Key.firstSeen) as? Date {
            FirebaseAnalytics.Analytics.setUserProperty(Self.weekKey(first), forName: "first_seen_week")
        }
        FirebaseAnalytics.Analytics.setUserProperty(HabitStore.shared.data.isPro ? "1" : "0", forName: "is_pro")
        Task {
            let type = BuildType.make(isDebug: Self.isDebugBuild, isSimulator: Self.isSimulator, isSandbox: await Self.isSandbox())
            FirebaseAnalytics.Analytics.setUserProperty(type.rawValue, forName: "build_type")
        }
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

    /// Приложение ушло в фон или его перекрыли: нажатия за этот заход уходят одним событием.
    func appResignedActive() {
        guard !gestureCounts.isEmpty else { return }
        let payload = Self.gesturePayload(gestureCounts)
        gestureCounts = [:]
        log("gestures", payload)
    }

    /// Параметры события gestures: число нажатий и свайпов по видам и всего.
    nonisolated static func gesturePayload(_ counts: [AnalyticsGestures.Kind: Int]) -> [String: Any] {
        var payload: [String: Any] = ["total": counts.values.reduce(0, +)]
        for (kind, count) in counts { payload[kind.rawValue] = count }
        return payload
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

    /// Показан ли экран сейчас (в том числе под листом): например, пейволл или онбординг.
    func isShowing(_ screen: AnalyticsScreen) -> Bool { screenStack.contains(screen) }

    /// Нажатие или жест (считает AnalyticsGestures). Не отправляется сразу: см. appResignedActive().
    func gesture(_ kind: AnalyticsGestures.Kind) {
        guard isActive else { return }
        gestureCounts[kind, default: 0] += 1
    }

    // MARK: Воронка активации (KAN-168)

    /// Показан шаг онбординга, с 1. Вызывать на каждую смену страницы: повтор того же шага не отправляется.
    func onboardingStep(_ step: Int) {
        guard sentOnboardingSteps.insert(step).inserted else { return }
        send(.onboardingStep(step))
    }

    /// Ответ на системный запрос уведомлений. Ещё и user property `notifications`, чтобы видеть по пользователям.
    func notificationPermission(granted: Bool) {
        send(.notificationPermissionResult(granted: granted))
        guard isActive else { return }
        FirebaseAnalytics.Analytics.setUserProperty(granted ? "granted" : "denied", forName: "notifications")
    }

    /// Привычку отметили выполненной. Первая отметка в жизни приложения уходит событием first_check.
    func habitChecked(now: Date = Date()) {
        guard let seconds = Self.firstCheckSeconds(defaults, now: now) else { return }
        send(.firstCheck(secondsSinceFirstOpen: seconds))
    }

    /// Секунды от первого запуска до первой отметки, если эта отметка первая (и запоминает, что она была).
    /// -1, если момент первого запуска неизвестен. nil - отметка не первая.
    nonisolated static func firstCheckSeconds(_ defaults: UserDefaults, now: Date) -> Int? {
        guard !defaults.bool(forKey: Key.firstCheckDone) else { return nil }
        defaults.set(true, forKey: Key.firstCheckDone)
        guard let first = defaults.object(forKey: Key.firstSeen) as? Date else { return -1 }
        return max(0, Int(now.timeIntervalSince(first)))
    }

    /// Редкое важное событие (покупка, пейвол, новая привычка...).
    func send(_ event: AnalyticsEvent) {
        var payload = event.payload
        if let value = event.floatValue { payload["value"] = value }
        payload["screen"] = currentScreen?.rawValue ?? "Other"
        log(event.type, payload)
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
