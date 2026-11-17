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
}
