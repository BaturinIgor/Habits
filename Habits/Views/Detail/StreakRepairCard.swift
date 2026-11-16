import SwiftUI

/// Предложение вернуть серию, которая прервалась из-за вчерашнего пропуска.
/// Показывается на экране «Сегодня» и на экране привычки.
struct StreakRepairCard: View {
    @Environment(HabitStore.self) private var store
    let habit: Habit
    let repair: (day: String, streak: Int)
    /// На экране «Сегодня» в карточке есть название привычки.
    var showName = false
    @State private var showingSparks = false

    private var canAfford: Bool { store.economy.balance >= Sparks.repairPrice }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 2) {
                Text(showName ? String(localized: "\(habit.name): the streak broke") : String(localized: "The streak broke"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("Bring back \(Fmt.days(repair.streak)) in a row for sparks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                if canAfford {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        _ = store.repairStreak(habit.id)
                    }
                } else {
                    showingSparks = true
                }
            } label: {
                SparkBadge(amount: Sparks.repairPrice)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel(Text("Bring back the streak for \(Sparks.repairPrice) sparks"))
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        }
        .sensoryFeedback(.success, trigger: store.data.wallet.repairs.count)
        .sheet(isPresented: $showingSparks) {
            SparksView()
        }
    }
}
