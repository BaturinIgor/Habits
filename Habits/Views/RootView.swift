import SwiftUI

enum AppTab: Hashable {
    case today
    case habits
    case stats
    case settings
}

struct RootView: View {
    @State private var selection: AppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "checkmark.circle.fill", value: AppTab.today) {
                TodayView()
            }
            Tab("Habits", systemImage: "square.stack.fill", value: AppTab.habits) {
                HabitsListView()
            }
            Tab("Statistics", systemImage: "chart.bar.fill", value: AppTab.stats) {
                StatsView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
