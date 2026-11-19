import SwiftUI
import WatchKit

@main
struct HabitsWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = WatchModel.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                TodayView()
            }
            .environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
    }
}

/// Сессию с iPhone подключаем при любом запуске, в том числе фоновом:
/// так компликация обновляется, даже когда приложение на часах закрыто.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in WatchModel.shared.start() }
    }

    /// Фоновые задачи: данные с iPhone (снимок, обновление компликации) и конец таймера.
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            let box = TaskBox(task)
            switch task {
            case is WKWatchConnectivityRefreshBackgroundTask:
                // Задачу нельзя завершать, пока WatchConnectivity не отдал всё, что пришло.
                Task { @MainActor in
                    WatchModel.shared.start()
                    await WatchModel.shared.waitForPendingContent()
                    box.task.setTaskCompletedWithSnapshot(false)
                }
            case is WKApplicationRefreshBackgroundTask:
                Task { @MainActor in
                    WatchModel.shared.start()
                    WatchModel.shared.refresh()
                    box.task.setTaskCompletedWithSnapshot(false)
                }
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}

/// Фоновая задача передаётся в главный поток, где её и завершают.
private struct TaskBox: @unchecked Sendable {
    let task: WKRefreshBackgroundTask
    init(_ task: WKRefreshBackgroundTask) { self.task = task }
}
