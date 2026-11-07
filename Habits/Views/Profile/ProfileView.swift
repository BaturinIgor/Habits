import SwiftUI

/// Вкладки нижней части профиля.
enum ProfileTab: String, CaseIterable, Identifiable {
    case achievements, avatars, backgrounds

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .achievements: "Achievements"
        case .avatars: "Avatars"
        case .backgrounds: "Backgrounds"
        }
    }
}

/// Профиль: уровень, ачивки и награды (аватарки и фоны) во вкладках.
struct ProfileView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false
    @State private var hint: Achievement?
    @State private var purchase: SparkPurchase?
    @State private var showingSparks = false
    @State private var showingPet = false
    @SceneStorage("profile.tab") private var tab: ProfileTab = .achievements

    private let grid = [GridItem(.adaptive(minimum: 96), spacing: 12)]
    private let smallGrid = [GridItem(.adaptive(minimum: 64), spacing: 12)]

    var body: some View {
        let facts = AchievementFacts(data: store.data)
        let unlocked = store.unlockedAchievementIDs
        let isPro = store.data.isPro
        let level = Achievements.level(totalDone: facts.totalDone)

        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Шапка
                    VStack(spacing: 10) {
                        AvatarView(reward: Rewards.avatar(store.data.settings.avatarID), size: 96)
                        Text("Level \(level.level)")
                            .font(.title2.weight(.bold))
                        ProgressView(value: level.progress)
                            .tint(.accentColor)
                            .frame(maxWidth: 220)
                        HStack(spacing: 18) {
                            Label("\(facts.totalDone)", systemImage: "checkmark.circle.fill")
                            Label("\(unlocked.count)/\(Achievements.all.count)", systemImage: "trophy.fill")
                            Label("\(facts.bestStreak)", systemImage: "flame.fill")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        Button {
                            showingSparks = true
                        } label: {
                            SparkBadge(amount: store.economy.balance, font: .headline)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                        }
                        .glassButtonStyle()
                    }
                    .padding(.top, 8)

                    PetCard { showingPet = true }

                    VStack(spacing: 16) {
                        Picker("Profile section", selection: $tab) {
                            ForEach(ProfileTab.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch tab {
                        case .achievements:
                            LazyVGrid(columns: grid, spacing: 12) {
                                ForEach(Achievements.all) { achievement in
                                    AchievementTile(achievement: achievement, facts: facts,
                                                    unlocked: unlocked.contains(achievement.id))
                                }
                            }
                        case .avatars:
                            LazyVGrid(columns: smallGrid, spacing: 12) {
                                PhotoRewardTile(slot: .avatar) { showingPaywall = true }
                                ForEach(Rewards.avatars) { reward in
                                    rewardButton(reward, unlocked: unlocked, isPro: isPro,
                                                 selected: store.data.settings.avatarID == reward.id) {
                                        AvatarView(reward: reward, size: 60)
                                    }
                                }
                            }
                        case .backgrounds:
                            LazyVGrid(columns: smallGrid, spacing: 12) {
                                PhotoRewardTile(slot: .background) { showingPaywall = true }
                                ForEach(Rewards.backgrounds) { reward in
                                    rewardButton(reward, unlocked: unlocked, isPro: isPro,
                                                 selected: store.data.settings.backgroundID == reward.id) {
                                        BackgroundSwatch(reward: reward).frame(height: 84)
                                    }
                                }
                            }
                        }
                    }
                    .animation(.snappy, value: tab)
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .sheet(isPresented: $showingSparks) { SparksView() }
            .sheet(isPresented: $showingPet) { PetView() }
            .sparkPurchaseAlert($purchase)
            .alert(
                Text(hint?.title ?? ""),
                isPresented: Binding(get: { hint != nil }, set: { if !$0 { hint = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Unlock: \(String(localized: hint?.detail ?? ""))")
            }
        }
    }

    private func rewardButton<Content: View>(_ reward: Reward, unlocked: Set<String>, isPro: Bool,
                                             selected: Bool, @ViewBuilder label: () -> Content) -> some View {
        let available = reward.isAvailable(unlocked: unlocked, isPro: isPro, purchased: store.data.wallet.purchases)
        return Button {
            if !available, let price = reward.price {
                let title = reward.kind == .avatar ? String(localized: "Avatar") : String(localized: "Background")
                purchase = SparkPurchase(title: title, price: price) { _ = store.buyReward(reward) }
            } else if available {
                withAnimation(.snappy) {
                    store.updateSettings {
                        if reward.kind == .avatar { $0.avatarID = reward.id } else { $0.backgroundID = reward.id }
                    }
                }
            } else if let achievement = Rewards.achievement(for: reward), !unlocked.contains(achievement.id) {
                hint = achievement
            } else {
                showingPaywall = true
            }
        } label: {
            label()
                .saturation(available || reward.price != nil ? 1 : 0)
                .opacity(available ? 1 : (reward.price != nil ? 0.8 : 0.45))
                .overlay(alignment: .topTrailing) {
                    if !available, let price = reward.price {
                        SparkBadge(amount: price, font: .caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(.background))
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    } else if !available {
                        if reward.needsPro && Rewards.achievement(for: reward).map({ unlocked.contains($0.id) }) ?? true {
                            ProBadge().scaleEffect(0.8)
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(Circle().fill(.black.opacity(0.45)))
                        }
                    } else if reward.needsPro {
                        ProBadge().scaleEffect(0.7)
                    }
                }
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .padding(-4)
                    }
                }
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.selection, trigger: selected)
    }
}

struct AchievementTile: View {
    let achievement: Achievement
    let facts: AchievementFacts
    let unlocked: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: achievement.icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(unlocked ? Color.white : Color.secondary)
                .frame(width: 56, height: 56)
                .background(Circle().fill(unlocked ? AnyShapeStyle(achievement.color.gradient) : AnyShapeStyle(.fill.tertiary)))
            Text(achievement.title)
                .font(.caption.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
            if unlocked {
                Text(achievement.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            // Низ плитки всегда одинаковый: полоса прогресса и счётчик прижаты к краю.
            VStack(spacing: 4) {
                ProgressView(value: Double(unlocked ? achievement.goal : achievement.progress(facts)),
                             total: Double(achievement.goal))
                    .tint(achievement.color)
                if unlocked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(achievement.color)
                } else {
                    Text(verbatim: "\(achievement.progress(facts))/\(achievement.goal)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 184, maxHeight: .infinity)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground)))
        .opacity(unlocked ? 1 : 0.8)
    }
}

/// Баннер о новой ачивке поверх приложения.
struct AchievementBanner: View {
    let achievement: Achievement
    var more: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: achievement.icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(achievement.color.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text("New achievement!")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(achievement.title)
                    .font(.headline)
                if more > 0 {
                    Text("And \(more) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        .padding(.horizontal, 16)
    }
}
