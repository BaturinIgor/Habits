import ActivityKit
import Foundation
import Observation
import UserNotifications

/// Таймер привычки (Pro): обратный отсчёт с Live Activity и уведомлением в конце.
/// Когда время вышло, привычка отмечается выполненной: сразу, если приложение открыто,
/// иначе при следующем открытии или кнопкой «Готово» в уведомлении.
@MainActor
@Observable
final class HabitTimer {
    static let shared = HabitTimer()

    struct Running: Codable, Equatable {
        let habitID: UUID
        let day: String
        let start: Date
        let end: Date

        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    private(set) var running: Running? {
        didSet { save() }
    }

    @ObservationIgnored private var waiter: Task<Void, Never>?
    private static let storageKey = "habitTimerRunning"

    private init() {
        if let raw = UserDefaults.standard.data(forKey: Self.storageKey) {
            running = try? JSONDecoder().decode(Running.self, from: raw)
        }
    }

    func isRunning(_ habitID: UUID) -> Bool {
        running?.habitID == habitID
    }

    // MARK: Управление

    func start(_ habit: Habit, minutes: Int) async {
        Analytics.shared.action(.timerStart)
        await stop()
        let now = Date()
        let end = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        let item = Running(habitID: habit.id, day: DayKey.make(now), start: now, end: end)
        running = item
        scheduleNotification(for: habit, item: item)
        startActivity(for: habit, item: item)
        wait(for: item)
    }

    /// Остановить без отметки.
    func cancel() async {
        await stop()
    }

    /// Закончить раньше и отметить привычку.
    func finishNow() async {
        guard let item = running else { return }
        await stop()
        markDone(item)
    }

    /// Проверка при открытии приложения и при обновлении в фоне: время могло выйти, пока нас не было.
    func checkFinished() async {
        guard let item = running else { return }
        if item.end <= Date() {
            await stop()
            markDone(item)
        } else if waiter == nil {
            wait(for: item)
        }
    }

    // MARK: Внутреннее

    private func wait(for item: Running) {
        waiter?.cancel()
        waiter = Task { [weak self] in
            let delay = item.end.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self?.checkFinished()
        }
    }

    private func stop() async {
        waiter?.cancel()
        waiter = nil
        if let item = running {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [Self.notificationID(item)]
            )
        }
        running = nil
        for activity in Activity<HabitTimerAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func markDone(_ item: Running) {
        let store = HabitStore.shared
        guard store.habit(item.habitID) != nil, let day = DayKey.date(item.day) else { return }
        // Человек мог уже отметить или пропустить вручную: не перетираем.
        if store.status(item.habitID, on: day) == nil {
            store.setStatus(.done, for: item.habitID, on: day)
        }
    }

    private func save() {
        if let running, let raw = try? JSONEncoder().encode(running) {
            UserDefaults.standard.set(raw, forKey: Self.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.storageKey)
        }
    }

    /// Номер 98: уведомления с суффиксами 98 и 99 не трогает общий пересчёт напоминаний.
    private static func notificationID(_ item: Running) -> String {
        NotificationPlanner.identifier(habitID: item.habitID, day: item.day, index: 98)
    }

    private func scheduleNotification(for habit: Habit, item: Running) {
        let content = UNMutableNotificationContent()
        if case .emoji(let emoji) = habit.icon {
            content.title = "\(emoji) \(habit.name)"
        } else {
            content.title = habit.name
        }
        content.body = String(localized: "Time's up. Well done!")
        content.sound = .default
        // Та же категория, что у напоминаний: в уведомлении есть кнопка «Готово».
        content.categoryIdentifier = NotificationPlanner.categoryID
        content.threadIdentifier = habit.id.uuidString
        content.userInfo = ["habitID": habit.id.uuidString, "day": item.day]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, item.duration), repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: Self.notificationID(item), content: content, trigger: trigger)
        )
    }

    private func startActivity(for habit: Habit, item: Running) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = HabitTimerAttributes(
            habitID: habit.id.uuidString,
            name: habit.name,
            icon: habit.icon,
            colorIndex: habit.colorIndex
        )
        let state = HabitTimerAttributes.ContentState(start: item.start, end: item.end)
        _ = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: item.end),
            pushType: nil
        )
    }
}
