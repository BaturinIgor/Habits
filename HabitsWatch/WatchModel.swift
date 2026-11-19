import Foundation
import Observation
import UserNotifications
import WatchConnectivity
import WatchKit
import WidgetKit

/// Данные на часах: снимок с iPhone, неподтверждённые отметки и таймер.
/// Привычки живут на iPhone, часы только просят их отметить.
@MainActor
@Observable
final class WatchModel {
    static let shared = WatchModel()

    private(set) var state: WatchState
    private(set) var timer: WatchTimerRun? {
        didSet { saveTimer() }
    }
    /// Текущее время для выбора дня: обновляется, когда приложение открывают.
    private(set) var now = Date()

    private static let timerKey = "watchTimerRun"
    private static let notificationID = "watch-timer"

    private let sessionDelegate = SessionDelegate()

    init() {
        state = WatchStateFile.load()
        if let raw = UserDefaults.standard.data(forKey: Self.timerKey) {
            timer = try? JSONDecoder().decode(WatchTimerRun.self, from: raw)
        }
        #if DEBUG
        if let demo = WatchDesign.state {
            state = demo
            timer = WatchDesign.timer
        }
        #endif
    }

    // MARK: Что показывать

    var todayKey: String { WatchDayKey.make(now) }
    var today: WatchDay? { state.day(todayKey) }
    var hasSnapshot: Bool { state.snapshot != nil }
    var isPro: Bool { state.snapshot?.isPro ?? false }

    func habit(_ id: UUID, day: String? = nil) -> WatchHabit? {
        state.day(day ?? todayKey)?.habits.first { $0.id == id }
    }

    // MARK: Связь с iPhone

    func start() {
        #if DEBUG
        if WatchDesign.isOn { return }
        #endif
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.delegate == nil else { return }
        session.delegate = sessionDelegate
        session.activate()
    }

    /// Приложение открыли: мог смениться день, а таймер — закончиться.
    func refresh() {
        now = Date()
        checkTimer()
        resendPending()
    }

    /// Неподтверждённые отметки, которых нет в очереди на доставку, отправляем заново.
    /// Повтор безопасен: отметка передаёт состояние, а не нажатие.
    private func resendPending() {
        guard !state.pending.isEmpty, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.outstandingUserInfoTransfers.isEmpty else { return }
        send(Array(state.pending.values))
    }

    /// Ждёт, пока WatchConnectivity передаст всё, что пришло в фоне (не дольше 15 секунд).
    func waitForPendingContent() async {
        guard WCSession.isSupported() else { return }
        for _ in 0..<30 {
            let session = WCSession.default
            if session.activationState == .activated && !session.hasContentPending { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    fileprivate func receive(_ payload: [String: Any]) {
        guard let raw = payload[WatchKeys.snapshot] as? Data,
              let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: raw) else { return }
        state.receive(snapshot)
        now = Date()
        save()
    }

    private func save() {
        WatchStateFile.save(state)
        WidgetCenter.shared.reloadAllTimelines()
    }

    fileprivate func send(_ marks: [WatchMark]) {
        guard !marks.isEmpty, let raw = try? JSONEncoder().encode(marks) else { return }
        let session = WCSession.default
        // До подключения отметки лежат в pending и уйдут после него.
        guard session.activationState == .activated else { return }
        let payload: [String: Any] = [WatchKeys.mark: raw]
        // В фоне ответа на сообщение можно не дождаться: часы уснут раньше, и запасной путь
        // через очередь не сработает. Поэтому в фоне сразу кладём отметки в очередь доставки.
        if session.isReachable && WKApplication.shared().applicationState == .active {
            let box = Payload(payload)
            session.sendMessage(payload, replyHandler: { @Sendable reply in
                let answer = Payload(reply)
                Task { @MainActor in WatchModel.shared.receive(answer.value) }
            }, errorHandler: { @Sendable _ in
                // iPhone недоступен прямо сейчас: передадим в очереди, она доставит позже.
                WCSession.default.transferUserInfo(box.value)
            })
        } else {
            session.transferUserInfo(payload)
        }
    }

    // MARK: Отметки

    /// Нажатие на привычку.
    func tap(_ habit: WatchHabit) {
        set(habit.tapped(), day: todayKey)
    }

    /// Отметить выполненной целиком (и количественную тоже).
    func complete(_ habit: WatchHabit) {
        guard !habit.done else { return }
        var next = habit
        next.done = true
        next.count = max(1, habit.target)
        next.skipped = false
        set(next, day: todayKey)
    }

    private func set(_ habit: WatchHabit, day: String) {
        record(WatchMark(habitID: habit.id, day: day, done: habit.done, count: habit.count, at: Date()))
    }

    private func record(_ mark: WatchMark) {
        state.pending[mark.key] = mark
        save()
        send([mark])
        WKInterfaceDevice.current().play(mark.done ? .success : .click)
    }

    // MARK: Таймер (Pro)

    func startTimer(_ habit: WatchHabit) {
        guard isPro, let minutes = habit.timerMinutes, minutes > 0 else { return }
        let start = Date()
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        timer = WatchTimerRun(habitID: habit.id, day: todayKey, start: start, end: end, target: habit.target)
        scheduleNotification(name: habit.name, after: end.timeIntervalSince(start))
        // Отметить привычку, даже если приложение к этому времени уйдёт в фон.
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: end, userInfo: nil) { _ in }
        WKInterfaceDevice.current().play(.start)
    }

    /// Остановить без отметки.
    func stopTimer() {
        timer = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        WKInterfaceDevice.current().play(.stop)
    }

    /// Закончить раньше и отметить.
    func finishTimer() {
        guard let run = timer else { return }
        timer = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        markDone(run)
    }

    /// Время вышло: отмечаем привычку.
    func checkTimer() {
        guard let run = timer, run.end <= Date() else { return }
        timer = nil
        markDone(run)
    }

    /// Отметка строится из самого таймера: после полуночи дня таймера в снимке уже может не быть.
    private func markDone(_ run: WatchTimerRun) {
        if let habit = self.habit(run.habitID, day: run.day), habit.done { return }
        record(run.completionMark(now: Date()))
    }

    private func saveTimer() {
        if let timer, let raw = try? JSONEncoder().encode(timer) {
            UserDefaults.standard.set(raw, forKey: Self.timerKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.timerKey)
        }
    }

    private func scheduleNotification(name: String, after seconds: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        let content = UNMutableNotificationContent()
        content.title = name
        content.body = String(localized: "Time's up. Well done!")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger)
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.add(request)
        }
    }
}

/// Делегат сессии отдельно от модели: WatchConnectivity требует NSObject.
private final class SessionDelegate: NSObject, WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = Payload(session.receivedApplicationContext)
        Task { @MainActor in
            let model = WatchModel.shared
            // Сначала отметки, сделанные до подключения: снимок может убрать их из pending
            // (например, если день уже сменился), и тогда они не ушли бы вовсе.
            model.send(Array(model.state.pending.values))
            model.receive(context.value)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let box = Payload(applicationContext)
        Task { @MainActor in WatchModel.shared.receive(box.value) }
    }

    /// Обновление компликации от iPhone приходит отдельной передачей.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let box = Payload(userInfo)
        Task { @MainActor in WatchModel.shared.receive(box.value) }
    }
}

/// Словари WatchConnectivity содержат только Data, поэтому их можно передать в главный поток.
private struct Payload: @unchecked Sendable {
    let value: [String: Any]
    init(_ value: [String: Any]) { self.value = value }
}
