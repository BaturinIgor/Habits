import SwiftUI

/// Профиль: уровень, ачивки и награды (аватарки и фоны).
struct ProfileView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false
    @State private var hint: Achievement?

    private let grid = [GridItem(.adaptive(minimum: 96), spacing: 12)]
    private let smallGrid = [GridItem(.adaptive(minimum: 64), spacing: 12)]

    var body: some View {
        let facts = AchievementFacts(data: store.data)
        let unlocked = Set(Achievements.all.filter { $0.isUnlocked(facts) }.map(\.id))
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
                    }
                    .padding(.top, 8)

                    section("Achievements") {
                        LazyVGrid(columns: grid, spacing: 12) {
                            ForEach(Achievements.all) { achievement in
                                AchievementTile(achievement: achievement, facts: facts,
                                                unlocked: unlocked.contains(achievement.id))
                            }
                        }
                    }

                    section("Avatars") {
                        LazyVGrid(columns: smallGrid, spacing: 12) {
                            PhotoRewardTile(slot: .avatar) { showingPaywall = true }
                            ForEach(Rewards.avatars) { reward in
                                rewardButton(reward, unlocked: unlocked, isPro: isPro,
                                             selected: store.data.settings.avatarID == reward.id) {
                                    AvatarView(reward: reward, size: 60)
                                }
                            }
                        }
                    }

                    section("Backgrounds") {
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
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(RewardBackground(reward: Rewards.background(store.data.settings.backgroundID)))
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
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

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.weight(.bold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rewardButton<Content: View>(_ reward: Reward, unlocked: Set<String>, isPro: Bool,
                                             selected: Bool, @ViewBuilder label: () -> Content) -> some View {
        let available = reward.isAvailable(unlocked: unlocked, isPro: isPro)
        return Button {
            if available {
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
                .saturation(available ? 1 : 0)
                .opacity(available ? 1 : 0.45)
                .overlay(alignment: .topTrailing) {
                    if !available {
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
                .lineLimit(2)
            if unlocked {
                Text(achievement.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            } else {
                ProgressView(value: Double(achievement.progress(facts)), total: Double(achievement.goal))
                    .tint(achievement.color)
                Text(verbatim: "\(achievement.progress(facts))/\(achievement.goal)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .top)
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
