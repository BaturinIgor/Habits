import CloudKit
import UIKit
import UserNotifications

/// Открытие ссылки-приглашения в семейную группу.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { await FamilySync.shared.accept(metadata) }
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { await FamilySync.shared.accept(cloudKitShareMetadata) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationPlanner.registerCategories()
        if FamilySync.isAvailable {
            // Тихие push от iCloud, когда родные меняют общую группу.
            application.registerForRemoteNotifications()
        }
        return true
    }

    /// Свой делегат сцены нужен, чтобы открыть приглашение в семейную группу.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    /// iCloud сообщил об изменениях в общей группе.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            await FamilySync.shared.syncAll()
            completionHandler(.newData)
        }
    }

    /// Показываем баннер, даже если приложение открыто.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Уведомление пришло при открытом приложении: оно уже увидено, номера следующих сдвигаем.
        Task { @MainActor in
            await NotificationPlanner.markSeen()
            await HabitStore.shared.reschedule()
        }
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
