import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationPlanner.registerCategories()
        return true
    }

    /// Показываем баннер, даже если приложение открыто.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// Кнопки "Готово" и "Пропустить" в уведомлении.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let habitID = (info["habitID"] as? String).flatMap { UUID(uuidString: $0) }
        let day = info["day"] as? String
        Task { @MainActor in
            await HabitStore.shared.handleNotificationAction(action, habitID: habitID, day: day)
            completionHandler()
        }
    }
}
