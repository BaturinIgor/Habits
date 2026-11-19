import SwiftUI

// Режим «Бросаю»: счётчик дней без вредной привычки, рекорд, вехи и сэкономленные деньги (Pro).

enum QuitFormat {
    /// Сумма в валюте телефона без копеек: "12 400 ₽".
    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0)))
    }

    /// Веха словами: "1 день", "неделя", "месяц", "год".
    static func milestone(_ days: Int) -> String {
        switch days {
        case 7: return String(localized: "a week")
        case 14: return String(localized: "two weeks")
        case 30: return String(localized: "a month")
        case 90: return String(localized: "three months")
        case 180: return String(localized: "half a year")
        case 365: return String(localized: "a year")
        default:
            if days > 365 && days % 365 == 0 { return String(localized: "\(days / 365) years") }
            return Fmt.days(days)
        }
    }
}

/// Карточка на экране «Сегодня».
struct QuitCard: View {
    let habit: Habit
    let showMoney: Bool
    var onOpen: () -> Void

    private var color: Color { Palette.color(habit.colorIndex) }

    var body: some View {
        let quit = habit.quit ?? QuitInfo()
        let days = quit.days()
        let next = quit.nextMilestone()
        Button(action: onOpen) {
            HStack(spacing: 14) {
                HabitIconView(icon: habit.icon, color: color, size: 46)
                VStack(alignment: .leading, spacing: 6) {
                    Text(habit.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    ProgressView(value: next.progress)
                        .tint(color)
                    HStack(spacing: 10) {
                        Text("Next: \(QuitFormat.milestone(next.days))")
                        if showMoney, let saved = quit.saved() {
                            Label(QuitFormat.money(saved), systemImage: "banknote")
                                .labelStyle(CompactLabelStyle())
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Text("\(days)")
                        .font(.title.weight(.bold).monospacedDigit())
                        .foregroundStyle(color)
                        .contentTransition(.numericText())
                    Text("days without")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 64)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Блок на экране привычки: счётчик, рекорд, деньги и кнопка «Сорвался».
struct QuitDetailSection: View {
    @Environment(HabitStore.self) private var store
    let habit: Habit
    @State private var confirmRelapse = false
    @State private var showingPaywall = false

    private var color: Color { Palette.color(habit.colorIndex) }

    var body: some View {
        let quit = habit.quit ?? QuitInfo()
        let next = quit.nextMilestone()
        VStack(spacing: 16) {
            VStack(spacing: 2) {
                Text("\(quit.days())")
                    .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                Text("days without it")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Since \(Fmt.backupDate(quit.since))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Next milestone: \(QuitFormat.milestone(next.days))")
                    .font(.footnote.weight(.semibold))
                ProgressView(value: next.progress)
                    .tint(color)
            }

            HStack(spacing: 12) {
                stat(value: "\(quit.best())", title: String(localized: "Best, days"))
                stat(value: "\(quit.totalDays())", title: String(localized: "Total, days"))
                stat(value: "\(quit.relapses.count)", title: String(localized: "Relapses"))
            }

            if store.data.isPro {
                if let saved = quit.saved() {
                    Label {
                        Text("Saved: \(QuitFormat.money(saved))")
                    } icon: {
                        Image(systemName: "banknote.fill").foregroundStyle(.green)
                    }
                    .font(.headline)
                }
            } else {
                Button {
                    showingPaywall = true
                } label: {
                    Label("See how much you've saved with Pro", systemImage: "crown.fill")
                        .font(.footnote)
                }
            }

            Button(role: .destructive) {
                confirmRelapse = true
            } label: {
                Label("I slipped", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .designAlert("relapse", $confirmRelapse)
        .confirmationDialog("Start the count again?", isPresented: $confirmRelapse, titleVisibility: .visible) {
            Button("I slipped", role: .destructive) {
                withAnimation { store.relapse(habit.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It happens. Your record and the total stay, and the count of days starts from now.")
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }

    private func stat(value: String, title: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
