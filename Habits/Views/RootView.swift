import StoreKit
import SwiftUI

enum AppTab: Hashable {
    case today
    case habits
    case stats
    case settings
}

struct RootView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.requestReview) private var requestReview
    @State private var selection: AppTab = .today
    @State private var banner: (achievement: Achievement, more: Int)?
    @State private var hideTask: Task<Void, Never>?
    @State private var lastBalance: Int?
    @State private var sparkGain: (id: Int, amount: Int)?
    @State private var showingWhatsNew = false
    @State private var showingNewHabit = false

    private var onboardingBinding: Binding<Bool> {
        Binding(get: { !store.data.settings.onboardingDone },
                set: { if !$0 { store.updateSettings { $0.onboardingDone = true } } })
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Today", systemImage: "checkmark.circle.fill") }
                .tag(AppTab.today)
            HabitsListView()
                .tabItem { Label("Habits", systemImage: "square.stack.fill") }
                .tag(AppTab.habits)
            StatsView()
                .tabItem { Label("Statistics", systemImage: "chart.bar.fill") }
                .tag(AppTab.stats)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .minimizeTabBarOnScroll()
        .overlay(alignment: .top) {
            if let banner {
                AchievementBanner(achievement: banner.achievement, more: banner.more)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation { self.banner = nil } }
            }
        }
        .overlay(alignment: .bottom) {
            if let gain = sparkGain {
                HStack(spacing: 4) {
                    Text(verbatim: "+")
                    SparkBadge(amount: gain.amount, font: .headline)
                }
                .font(.headline)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassBackground(in: Capsule())
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(gain.id)
                .allowsHitTesting(false)
            }
        }
        .sensoryFeedback(.success, trigger: banner?.achievement.id)
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView()
        }
        .sheet(isPresented: $showingWhatsNew, onDismiss: {
            store.updateSettings { $0.whatsNewSeen = WhatsNewView.version }
        }) {
            WhatsNewView {
                showingWhatsNew = false
                // Окно новой привычки открываем после закрытия этого.
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    showingNewHabit = true
                }
            }
        }
        .sheet(isPresented: $showingNewHabit) {
            HabitEditorView(habit: nil)
        }
        .task {
            // Тем, кто обновился, один раз показываем новые возможности.
            let settings = store.data.settings
            if settings.onboardingDone && settings.whatsNewSeen != WhatsNewView.version {
                try? await Task.sleep(for: .seconds(1))
                showingWhatsNew = true
            }
        }
        .task(id: store.revision) {
            checkAchievements()
            store.claimProGift()
            store.syncPetStage()
            store.syncEarnedSnapshot()
            showSparkGain()
            if store.data.settings.onboardingDone {
                RatingPrompt.maybeAsk(data: store.data, requestReview: requestReview)
            }
        }
    }

    /// Всплывающее "+N искр", когда баланс вырос.
    private func showSparkGain() {
        let balance = store.economy.balance
        defer { lastBalance = balance }
        guard let last = lastBalance, balance > last, store.data.settings.onboardingDone else { return }
        let id = (sparkGain?.id ?? 0) + 1
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            sparkGain = (id, balance - last)
        }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if sparkGain?.id == id {
                withAnimation { sparkGain = nil }
            }
        }
    }

    /// Показывает баннер, если появились новые ачивки.
    private func checkAchievements() {
        guard store.data.settings.onboardingDone else { return }
        let unlocked = store.unlockedAchievementIDs
        let seen = Set(store.data.settings.seenAchievements)
        let fresh = Achievements.all.filter { unlocked.contains($0.id) && !seen.contains($0.id) }
        guard let first = fresh.first else { return }
        store.updateSettings { $0.seenAchievements = Array(seen.union(unlocked)).sorted() }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            banner = (first, fresh.count - 1)
        }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation { banner = nil }
        }
    }
}
