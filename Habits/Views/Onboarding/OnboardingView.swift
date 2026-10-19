import SwiftUI

/// Короткое знакомство с приложением: 4 экрана.
struct OnboardingView: View {
    @Environment(HabitStore.self) private var store
    @State private var page = 0

    private struct Page {
        let icon: String
        let color: Color
        let title: LocalizedStringKey
        let text: LocalizedStringKey
    }

    private let pages: [Page] = [
        Page(icon: "checkmark.circle.fill", color: .accentColor, title: "Small steps every day",
             text: "Track habits, get gentle reminders and watch your streaks grow."),
        Page(icon: "hand.draw.fill", color: .orange, title: "Simple gestures",
             text: "Tap the circle or swipe right to check off. Swipe left to skip, add a note or edit. The arrows button at the top changes the order."),
        Page(icon: "snowflake", color: .cyan, title: "Misses are okay",
             text: "Two misses a month won't break your streak, and a minimum version still counts on hard days."),
        Page(icon: "trophy.fill", color: .yellow, title: "Achievements and rewards",
             text: "Earn achievements to unlock avatars and backgrounds, and level up with every check-in."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    let item = pages[index]
                    VStack(spacing: 22) {
                        Spacer()
                        Image(systemName: item.icon)
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 140, height: 140)
                            .background(Circle().fill(item.color.gradient))
                            .shadow(color: item.color.opacity(0.35), radius: 20, y: 10)
                        Text(item.title)
                            .font(.largeTitle.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(item.text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 10) {
                Button {
                    if page < pages.count - 1 {
                        withAnimation(.snappy) { page += 1 }
                    } else {
                        finish()
                    }
                } label: {
                    Text(page < pages.count - 1 ? String(localized: "Continue") : String(localized: "Let's go"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                if page < pages.count - 1 {
                    Button("Skip") { finish() }
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
    }

    private func finish() {
        store.updateSettings { $0.onboardingDone = true }
        Task {
            await NotificationPlanner.requestAuthorizationIfNeeded()
            await store.reschedule()
        }
    }
}
