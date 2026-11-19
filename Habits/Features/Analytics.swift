import CryptoKit
import Foundation
import SwiftUI
import UIKit

/// Анонимная статистика через TelemetryDeck (свой маленький клиент к Ingest API v2, без SDK).
///
/// Бесплатный тариф TelemetryDeck ограничен числом событий в месяц, поэтому:
/// - экраны, переходы, нажатия, свайпы и действия только считаются в телефоне
///   и раз в день уходят одним событием `Usage.daily` со всеми счётчиками;
/// - сразу уходят только редкие важные события из `AnalyticsEvent` (покупка, пейвол, новая привычка...).
/// Так на одного активного пользователя выходит около 50 событий в месяц.
///
/// Личные данные не отправляются никогда: ни названий привычек, ни заметок, ни текста настроения.
/// Ключи счётчиков берутся только из перечислений в AnalyticsCatalog.swift.
/// Пользователь — случайный UUID этого устройства (TelemetryDeck дополнительно хэширует его у себя).
/// Без App ID (сборка для SideStore, локальная сборка) и в автотестах ничего не отправляется.
@MainActor
final class Analytics {
    static let shared = Analytics()

    /// Выключатель в настройках. Хранится только на устройстве.
    static let optOutKey = "analyticsOptOut"

    private let defaults = UserDefaults.standard
    private let appID: String
    private let endpoint = URL(string: "https://nom.telemetrydeck.com/v2/")!

    /// Экраны, открытые сейчас (последний — тот, что видит пользователь).
    private var screenStack: [(screen: AnalyticsScreen, since: Date)] = []
    private var lastScreen: AnalyticsScreen?
    private var sessionStart: Date?
    private var flushing = false
    /// Счётчики за текущий день держим в памяти и сохраняем пачками.
    private lazy var counters: [String: Int] = defaults.dictionary(forKey: Key.counters) as? [String: Int] ?? [:]
    private var unsaved = 0

    private enum Key {
        static let user = "analytics.user"
        static let counters = "analytics.counters"
        static let countersDay = "analytics.countersDay"
        static let queue = "analytics.queue"
        static let installSent = "analytics.installSent"
        static let firstLaunch = "analytics.firstLaunch"
    }

    private init() {
        appID = (Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Работает ли отправка: есть App ID, не автотест и пользователь не выключил.
    var isActive: Bool {
        !appID.isEmpty && !TestMode.isUITest && !defaults.bool(forKey: Self.optOutKey)
    }

    // MARK: Жизненный цикл

    /// Приложение стало активным: новая сессия, отправка вчерашних счётчиков и очереди.
    func appBecameActive() {
        AnalyticsGestures.attachToWindows()
        guard isActive else { return }
        if defaults.object(forKey: Key.firstLaunch) == nil {
            defaults.set(Date(), forKey: Key.firstLaunch)
        }
        if !defaults.bool(forKey: Key.installSent) {
            defaults.set(true, forKey: Key.installSent)
            send(.appInstalled(isUpdate: HabitStore.shared.data.settings.onboardingDone))
        }
        sessionStart = Date()
        // Время в фоне не считаем.
        if !screenStack.isEmpty { screenStack[screenStack.count - 1].since = sessionStart ?? Date() }
        count("Session.count")
        rollOverIfNeeded()
        flush()
    }

    /// Приложение ушло в фон: дописываем время сессии и экрана, отправляем очередь.
    func appWentToBackground() {
        guard isActive else { return }
        if let start = sessionStart {
            count("Session.seconds", by: Int(Date().timeIntervalSince(start)))
            sessionStart = nil
        }
        if let top = screenStack.last {
            count("Time.\(top.screen.rawValue)", by: Int(Date().timeIntervalSince(top.since)))
            screenStack[screenStack.count - 1].since = Date()
        }
        saveCounters()
        flush(inBackground: true)
    }

    /// Пользователь выключил или включил статистику в настройках.
    func setEnabled(_ enabled: Bool) {
        defaults.set(!enabled, forKey: Self.optOutKey)
        if !enabled {
            // Ничего из накопленного не отправляем.
            counters = [:]
            defaults.removeObject(forKey: Key.counters)
            defaults.removeObject(forKey: Key.queue)
        }
    }

    // MARK: Экраны и действия (только счётчики)

    func screenAppeared(_ screen: AnalyticsScreen) {
        let now = Date()
        if let top = screenStack.last {
            count("Time.\(top.screen.rawValue)", by: Int(now.timeIntervalSince(top.since)))
            screenStack[screenStack.count - 1].since = now
        }
        screenStack.removeAll { $0.screen == screen }
        screenStack.append((screen, now))
        count("Screen.\(screen.rawValue)")
        if let lastScreen, lastScreen != screen {
            count("Flow.\(lastScreen.rawValue)>\(screen.rawValue)")
        }
        lastScreen = screen
    }

    func screenDisappeared(_ screen: AnalyticsScreen) {
        guard let index = screenStack.lastIndex(where: { $0.screen == screen }) else { return }
        count("Time.\(screen.rawValue)", by: Int(Date().timeIntervalSince(screenStack[index].since)))
        screenStack.remove(at: index)
        if let top = screenStack.last {
            screenStack[screenStack.count - 1].since = Date()
            if lastScreen != top.screen {
                count("Flow.\(screen.rawValue)>\(top.screen.rawValue)")
                lastScreen = top.screen
            }
        }
    }

    /// Экран, на котором сейчас пользователь (для подсчёта жестов).
    var currentScreen: AnalyticsScreen? { screenStack.last?.screen }

    /// Действие пользователя: кнопка, переключатель, отметка привычки.
    func action(_ action: AnalyticsAction) {
        count("Action.\(action.rawValue)")
    }

    /// Нажатие или жест на текущем экране (считает AnalyticsGestures).
    func gesture(_ kind: AnalyticsGestures.Kind) {
        count("Gesture.\(currentScreen?.rawValue ?? "Other").\(kind.rawValue)")
    }

    // MARK: Важные события (уходят сразу)

    func send(_ event: AnalyticsEvent) {
        guard isActive else { return }
        var payload = defaultPayload()
        for (key, value) in event.payload { payload[key] = value }
        enqueue(type: event.type, payload: payload, floatValue: event.floatValue)
        // Важные события отправляем пачкой: при уходе в фон или сразу, если это покупка.
        if event.isUrgent { flush() }
    }

    // MARK: Счётчики

    private func count(_ key: String, by value: Int = 1) {
        guard isActive, value > 0 else { return }
        rollOverIfNeeded()
        // Ограничение на случай ошибки: не больше 400 разных ключей в день.
        guard counters[key] != nil || counters.count < 400 else { return }
        counters[key, default: 0] += value
        unsaved += 1
        if unsaved >= 20 { saveCounters() }
    }

    private func saveCounters() {
        unsaved = 0
        defaults.set(counters, forKey: Key.counters)
    }

    /// Если накопленные счётчики за прошлый день, отправляем их одним событием и начинаем заново.
    private func rollOverIfNeeded() {
        let today = DayKey.make(Date())
        let day = defaults.string(forKey: Key.countersDay)
        guard day != today else { return }
        defaults.set(today, forKey: Key.countersDay)
        let counters = self.counters
        self.counters = [:]
        saveCounters()
        guard let day, !counters.isEmpty else { return }
        var payload = defaultPayload()
        payload["Usage.day"] = day
        for (key, value) in counters { payload[key] = value }
        for (key, value) in AnalyticsSnapshot.make(HabitStore.shared.data) { payload[key] = value }
        if let first = defaults.object(forKey: Key.firstLaunch) as? Date {
            payload["User.daysSinceInstall"] = max(0, Calendar.app.dateComponents([.day], from: first, to: Date()).day ?? 0)
        }
        enqueue(type: "Usage.daily", payload: payload, floatValue: Double(counters["Session.seconds"] ?? 0))
    }

    // MARK: Параметры каждого события

    private func defaultPayload() -> [String: Any] {
        let info = Bundle.main.infoDictionary
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let locale = Locale.current
        var payload: [String: Any] = [
            "TelemetryDeck.AppInfo.version": info?["CFBundleShortVersionString"] as? String ?? "",
            "TelemetryDeck.AppInfo.buildNumber": info?["CFBundleVersion"] as? String ?? "",
            "TelemetryDeck.Device.operatingSystem": "iOS",
            "TelemetryDeck.Device.systemVersion": "\(os.majorVersion).\(os.minorVersion)",
            "TelemetryDeck.Device.systemMajorVersion": "\(os.majorVersion)",
            "TelemetryDeck.Device.modelName": Self.modelName,
            "TelemetryDeck.RunContext.locale": locale.identifier,
            "TelemetryDeck.RunContext.language": Bundle.main.preferredLocalizations.first ?? "",
            "TelemetryDeck.UserPreference.language": locale.language.languageCode?.identifier ?? "",
            "TelemetryDeck.UserPreference.region": locale.region?.identifier ?? "",
            "TelemetryDeck.RunContext.isTestFlight": Self.isTestFlight,
            "TelemetryDeck.RunContext.isAppStore": !Self.isTestFlight && !Self.isDebug,
            "User.isPro": HabitStore.shared.data.isPro,
        ]
        if let first = defaults.object(forKey: Key.firstLaunch) as? Date {
            payload["User.installWeek"] = Self.weekKey(first)
        }
        return payload
    }

    #if DEBUG
    private static let isDebug = true
    #else
    private static let isDebug = false
    #endif

    private static let isTestFlight: Bool =
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"

    private static let modelName: String = {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }()

    /// Неделя установки вида 2026-W47: для когорт удержания.
    private static func weekKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    private var clientUser: String {
        if let saved = defaults.string(forKey: Key.user) { return saved }
        let raw = UUID().uuidString
        let hash = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        defaults.set(hash, forKey: Key.user)
        return hash
    }

    // MARK: Очередь и отправка

    private func enqueue(type: String, payload: [String: Any], floatValue: Double?) {
        var signal: [String: Any] = [
            "appID": appID,
            "clientUser": clientUser,
            "type": type,
            "isTestMode": Self.isDebug,
            "receivedAt": ISO8601DateFormatter().string(from: Date()),
            "payload": payload,
        ]
        if let floatValue { signal["floatValue"] = floatValue }
        var queue = storedQueue()
        queue.append(signal)
        // Если сети долго нет, старое выбрасываем, чтобы очередь не росла бесконечно.
        if queue.count > 100 { queue.removeFirst(queue.count - 100) }
        if let data = try? JSONSerialization.data(withJSONObject: queue) {
            defaults.set(data, forKey: Key.queue)
        }
    }

    private func storedQueue() -> [[String: Any]] {
        guard let data = defaults.data(forKey: Key.queue),
              let queue = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return queue
    }

    private func flush(inBackground: Bool = false) {
        guard isActive, !flushing else { return }
        let queue = storedQueue()
        guard !queue.isEmpty, let body = try? JSONSerialization.data(withJSONObject: queue) else { return }
        flushing = true
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 20
        let task = BackgroundTask()
        if inBackground { task.begin() }
        let sent = queue.count
        Task {
            let ok: Bool
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                // 4xx кроме 429: запрос не примут и потом, повторять смысла нет.
                ok = (200..<300).contains(status) || ((400..<500).contains(status) && status != 429)
            } catch {
                ok = false
            }
            if ok {
                var rest = storedQueue()
                rest.removeFirst(min(sent, rest.count))
                if let data = try? JSONSerialization.data(withJSONObject: rest) {
                    defaults.set(data, forKey: Key.queue)
                }
            }
            flushing = false
            task.end()
        }
    }
}

/// Немного времени в фоне, чтобы успеть отправить очередь.
@MainActor
private final class BackgroundTask {
    private var id: UIBackgroundTaskIdentifier = .invalid

    func begin() {
        id = UIApplication.shared.beginBackgroundTask(withName: "analytics") { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

// MARK: - Отметка экрана

extension View {
    /// Считает показы экрана, время на нём и переходы между экранами.
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
