import SwiftUI

/// Предложение перенести напоминание ближе к обычному времени отметки (KAN-135).
/// Показывается на экране привычки, когда «Умное время» выключено, а напоминание стабильно
/// приходит намного раньше или позже. «Не сейчас» прячет карточку на две недели.
struct SmartTimeCard: View {
    @Environment(HabitStore.self) private var store
    let habit: Habit
    let suggestion: SmartTime.Suggestion
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2)
                    .foregroundStyle(Palette.color(habit.colorIndex))
                VStack(alignment: .leading, spacing: 2) {
                    Text("You usually check it off around \(suggestion.typical.text)")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("The reminder comes at \(suggestion.current.text). Move it to \(suggestion.suggested.text)?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button {
                    withAnimation(.snappy) {
                        store.acceptSmartTime(suggestion, for: habit.id)
                        onClose()
                    }
                } label: {
                    Text("Move to \(suggestion.suggested.text)")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.color(habit.colorIndex))
                .accessibilityIdentifier("smartTime.accept")
                Button {
                    SmartTimeDismissals.dismiss(habit.id)
                    Analytics.shared.send(.smartTimeDismissed(shiftMinutes: suggestion.shiftMinutes))
                    withAnimation(.snappy) { onClose() }
                } label: {
                    Text("Not now")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .accessibilityIdentifier("smartTime.dismiss")
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.color(habit.colorIndex).opacity(0.10))
        }
        .accessibilityElement(children: .contain)
        .onAppear {
            // Событие «предложение показано» - не чаще раза в день на привычку.
            if SmartTimeDismissals.markShownToday(habit.id) {
                Analytics.shared.send(.smartTimeSuggested(shiftMinutes: suggestion.shiftMinutes))
            }
        }
    }
}

/// Отказы от предложения хранятся только на устройстве: это не данные привычки и не уходят родным.
enum SmartTimeDismissals {
    /// После «Не сейчас» карточка снова появится через столько дней.
    static let quietDays = 14
    private static let defaults = UserDefaults.standard

    static func isDismissed(_ id: UUID, now: Date = Date()) -> Bool {
        guard let date = defaults.object(forKey: "smartTime.dismissed.\(id.uuidString)") as? Date else { return false }
        return now.timeIntervalSince(date) < Double(quietDays) * 86_400
    }

    static func dismiss(_ id: UUID, now: Date = Date()) {
        defaults.set(now, forKey: "smartTime.dismissed.\(id.uuidString)")
    }

    /// true, если сегодня карточку этой привычки ещё не показывали.
    static func markShownToday(_ id: UUID) -> Bool {
        let key = "smartTime.shown.\(id.uuidString)"
        let today = DayKey.make(Date())
        guard defaults.string(forKey: key) != today else { return false }
        defaults.set(today, forKey: key)
        return true
    }
}
