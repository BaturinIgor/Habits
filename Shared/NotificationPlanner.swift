import Foundation
import UserNotifications

/// Планирует локальные уведомления.
///
/// iOS хранит не больше 64 запланированных уведомлений на приложение,
/// поэтому план пересобирается целиком при каждом изменении:
/// ближайшие 36 часов получают основное напоминание и все повторы,
/// дальше на 30 дней вперёд ставятся только основные напоминания.
@MainActor
enum NotificationPlanner {
    static let categoryID = "HABIT_REMINDER"
    static let doneAction = "HABIT_DONE"
    static let skipAction = "HABIT_SKIP"

    private static let maxPending = 64
    private static let horizonDays = 30
    private static let nearWindow: TimeInterval = 36 * 3600
    private static var generation = 0

    struct Event {
        let id: String
        let date: Date
        let habit: Habit
        let day: String
        let index: Int
    }

    nonisolated static func identifier(habitID: UUID, day: String, index: Int) -> String {
        "\(habitID.uuidString)|\(day)|\(index)"
    }

    // MARK: Настройка

    static func registerCategories() {
        let done = UNNotificationAction(
            identifier: doneAction,
            title: String(localized: "Done"),
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "checkmark.circle.fill")
        )
        let skip = UNNotificationAction(
            identifier: skipAction,
            title: String(localized: "Skip"),
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "forward.fill")
        )
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [done, skip],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func requestAuthorizationIfNeeded() async {
        if await authorizationStatus() == .notDetermined {
            await requestAuthorization()
        }
    }

    // MARK: Планирование

    static func reschedule(data: AppData, now: Date = Date()) async {
        generation += 1
        let token = generation
        let status = await authorizationStatus()
        // Пока ждали ответа, мог начаться более свежий пересчёт.
        guard token == generation else { return }

        // Без разрешения ничего не трогаем: очередь всё равно не будет показана.
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for event in plan(data: data, now: now) {
            center.add(makeRequest(event), withCompletionHandler: nil)
        }
    }

    /// Убирает из Центра уведомлений уже показанные напоминания по этой привычке за этот день.
    static func clearDelivered(habitID: UUID, day: String) async {
        let center = UNUserNotificationCenter.current()
        let prefix = "\(habitID.uuidString)|\(day)|"
        let delivered = await center.deliveredNotifications()
        let ids = delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
        if !ids.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    static func pendingCount() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests().count
    }

    static func plan(data: AppData, now: Date) -> [Event] {
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: now)
        let nearLimit = now.addingTimeInterval(nearWindow)

        var near: [Event] = []
        var far: [Event] = []

        for habit in data.habits where !habit.isArchived {
            guard let reminder = habit.reminder else { continue }
            let rule = habit.repeatRule(isPro: data.isPro)
            let repeatCount = max(0, min(rule.count, 40))
            let interval = TimeInterval(max(1, rule.interval) * 60)
            // Начинаем со вчерашнего дня: повторы позднего напоминания могут перейти через полночь.
            for offset in -1...horizonDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      habit.isScheduled(on: day, calendar: calendar),
                      let fire = reminder.date(on: day, calendar: calendar) else { continue }
                let key = DayKey.make(day, calendar: calendar)
                if data.status(habit.id, day: key) != nil { continue }

                for index in 0...repeatCount {
                    let date = fire.addingTimeInterval(Double(index) * interval)
                    guard date > now.addingTimeInterval(2) else { continue }
                    let event = Event(
                        id: identifier(habitID: habit.id, day: key, index: index),
                        date: date,
                        habit: habit,
                        day: key,
                        index: index
                    )
                    if date <= nearLimit {
                        near.append(event)
                    } else if index == 0 {
                        far.append(event)
                    }
                }
            }
        }

        near.sort { $0.date < $1.date }
        far.sort { $0.date < $1.date }
        return Array((near + far).prefix(maxPending))
    }

    private static func makeRequest(_ event: Event) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        let habit = event.habit
        if case .emoji(let emoji) = habit.icon {
            content.title = "\(emoji) \(habit.name)"
        } else {
            content.title = habit.name
        }
        if event.index == 0 {
            content.body = habit.details.isEmpty ? String(localized: "Time for your habit") : habit.details
        } else {
            content.body = String(localized: "Reminder again. Check it off when you're done.")
        }
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.threadIdentifier = habit.id.uuidString
        content.interruptionLevel = .active
        content.userInfo = ["habitID": habit.id.uuidString, "day": event.day]

        let components = Calendar.app.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: event.date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: event.id, content: content, trigger: trigger)
    }
}
