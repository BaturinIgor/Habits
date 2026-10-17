import SwiftUI

/// Экран Pro. Покупки появятся после публикации в App Store,
/// пока Pro включается тестовым переключателем в настройках.
struct PaywallView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private struct Feature: Identifiable {
        let icon: String
        let title: LocalizedStringKey
        let text: LocalizedStringKey
        var id: String { icon }
    }

    private let features: [Feature] = [
        Feature(icon: "infinity", title: "Unlimited habits",
                text: "The free version has up to 5 active habits."),
        Feature(icon: "bell.badge.fill", title: "Custom reminder repeats",
                text: "Choose how many times and how often each reminder repeats."),
        Feature(icon: "drop.fill", title: "Daily goals",
                text: "Count glasses of water, pages or minutes toward a goal."),
        Feature(icon: "pause.circle.fill", title: "Pause",
                text: "Take a break for a trip or illness without losing your streak."),
        Feature(icon: "person.2.fill", title: "Family",
                text: "Coming soon: follow your child's progress."),
        Feature(icon: "icloud.fill", title: "Sync and backup",
                text: "Coming soon: your habits on all your devices."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(Circle().fill(LinearGradient(
                            colors: [Color(red: 1, green: 0.62, blue: 0.26), Color(red: 0.92, green: 0.23, blue: 0.35)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )))
                        .shadow(color: .orange.opacity(0.35), radius: 18, y: 8)
                        .padding(.top, 12)

                    VStack(spacing: 6) {
                        Text("Habit Tracker Pro")
                            .font(.largeTitle.weight(.bold))
                        Text("More freedom for the habits that matter.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(features) { feature in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: feature.icon)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.accentColor.gradient))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(feature.title)
                                        .font(.headline)
                                    Text(feature.text)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 18, cornerRadius: 24)

                    if store.data.isPro {
                        Label("Pro is active", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                    } else {
                        Button {
                        } label: {
                            Text("Available after App Store release")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(true)
                    }

                    Text("Purchases will be available once the app is published. Until then, Pro can be turned on for testing in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .background(AppBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }
}

/// Небольшая метка "PRO" рядом с платными функциями.
struct ProBadge: View {
    var body: some View {
        Text(verbatim: "PRO")
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(LinearGradient(
                colors: [Color(red: 1, green: 0.62, blue: 0.26), Color(red: 0.92, green: 0.23, blue: 0.35)],
                startPoint: .leading, endPoint: .trailing
            )))
    }
}
