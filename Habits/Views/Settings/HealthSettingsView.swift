import SwiftUI

/// Настройки → Apple Health: что приложение читает из «Здоровья», какие привычки связаны
/// и где управлять доступом. Виден всем (и без Pro), чтобы интеграция с HealthKit
/// была заметна в интерфейсе (App Review 2.5.1).
struct HealthSettingsView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var showingPaywall = false
    /// Макеты: сразу прокрутить к связанным привычкам.
    var scrollToLinked = false

    static let healthAppURL = URL(string: "x-apple-health://")!

    private var linked: [Habit] {
        store.data.activeHabits.filter { $0.health != nil && !$0.isQuit }
    }

    var body: some View {
        analyticsBody.analyticsScreen(.healthSettings)
    }

    @ViewBuilder private var analyticsBody: some View {
        ScrollViewReader { proxy in
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HealthIcon(size: 44)
                    Text("ZenHab works with Apple Health")
                        .font(.title3.weight(.bold))
                    Text("Link a habit to steps, sleep, water, exercise, workouts or mindful minutes. When you reach the goal in the Health app, the habit is checked off by itself.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section {
                ForEach(HealthLink.Metric.allCases) { metric in
                    Label(metric.title, systemImage: metric.symbol)
                }
            } header: {
                Text("What ZenHab reads")
            } footer: {
                Text("ZenHab only reads these data and never writes to Apple Health. Health data is not stored or sent anywhere: only the check-off of the habit is saved.")
            }

            Section {
                if !store.data.isPro {
                    Button {
                        showingPaywall = true
                    } label: {
                        HStack(spacing: 8) {
                            Text("Check off habits by Apple Health")
                                .foregroundStyle(Color.primary)
                            ProBadge()
                            Spacer()
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if linked.isEmpty {
                    Text("No habits are linked yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(linked) { habit in
                        if let link = habit.health {
                            LabeledContent {
                                Text(link.metric.format(link.goal))
                            } label: {
                                Label {
                                    Text(habit.name)
                                } icon: {
                                    Image(systemName: link.metric.symbol)
                                        .foregroundStyle(HealthIcon.tint)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Linked habits")
                    .id("linked")
            } footer: {
                Text("To link a habit, open it and choose Apple Health → Check off by.")
            }

            Section {
                Button {
                    openURL(Self.healthAppURL)
                } label: {
                    Label("Open the Health app", systemImage: "arrow.up.forward.app")
                }
            } footer: {
                Text("You can allow or deny access to each type of data in Settings → Privacy & Security → Health → ZenHab.")
            }
        }
        .onAppear {
            guard scrollToLinked else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo("linked", anchor: .top) }
        }
        }
        .appBackground()
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPaywall) {
            PaywallView(highlight: .health)
        }
    }
}

/// Значок «Здоровья»: белое сердце на розово-красном фоне.
struct HealthIcon: View {
    static let tint = Color(red: 1.0, green: 0.18, blue: 0.33)
    var size: CGFloat = 29

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Self.tint.gradient)
            )
            .accessibilityHidden(true)
    }
}
