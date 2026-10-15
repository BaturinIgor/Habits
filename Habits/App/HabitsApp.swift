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
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .task {
                    await NotificationPlanner.requestAuthorizationIfNeeded()
                    await store.reschedule()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.reloadFromDisk()
                Task { await store.reschedule() }
            case .background:
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
        await HabitStore.shared.reschedule()
    }
}
