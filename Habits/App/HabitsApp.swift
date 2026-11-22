import BackgroundTasks
import SwiftUI

@main
struct HabitsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = HabitStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task {
                    #if DEBUG
                    if TestMode.isUITest { HangWatchdog.shared.start() }
                    #endif
                    ProStore.shared.start()
                    // Блокировка по Face ID при запуске.
                    AppLock.shared.lock()
                    await AppLock.shared.unlockIfNeeded()
                    // В первый день после онбординга разрешение спрашивает карточка после первой отметки (KAN-169).
                    if store.data.settings.onboardingDone && !store.data.settings.firstDayGuide {
                        await NotificationPlanner.requestAuthorizationIfNeeded()
                    }
                    await store.reschedule()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.reloadFromDisk()
                // Умное время: напоминания подстраиваются под обычное время отметки (KAN-135).
                store.applySmartTimes()
                Analytics.shared.appBecameActive()
                Task { await AppLock.shared.unlockIfNeeded() }
                Task {
                    // Пользователь в приложении: новые уведомления увидены, счётчик на иконке с нуля.
                    await NotificationPlanner.markSeen()
                    // Таймер мог закончиться, пока приложение было закрыто.
                    await HabitTimer.shared.checkFinished()
                    await store.reschedule()
                    await ProStore.shared.refreshEntitlements()
                    await FamilySync.shared.syncAll()
                    await HealthSync.shared.sync()
                }
                // Пока приложение открыто, изменения родных подтягиваем сами, не дожидаясь push.
                FamilySync.shared.startLiveUpdates()
            case .background:
                Analytics.shared.appResignedActive()
                AppLock.shared.lock()
                FamilySync.shared.flushBeforeBackground()
                CloudBackup.shared.backupBeforeBackground()
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
    }
}

/// Периодический пересчёт уведомлений в фоне, чтобы очередь не пустела,
/// даже если приложение долго не открывать.
enum BackgroundRefresh {
    static let identifier = "com.personal.habits.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(3 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func run() async {
        schedule()
        HabitStore.shared.reloadFromDisk()
        await FamilySync.shared.syncAll()
        await HealthSync.shared.sync()
        await HabitTimer.shared.checkFinished()
        await HabitStore.shared.reschedule()
        await CloudBackup.shared.backupIfNeeded()
    }
}
