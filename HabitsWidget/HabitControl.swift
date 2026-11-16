import AppIntents
import SwiftUI
import WidgetKit

/// Кнопка привычки для Пункта управления, экрана блокировки и кнопки действия (iOS 18).
/// Нажатие отмечает привычку за сегодня, повторное снимает отметку.
@available(iOS 18.0, *)
struct HabitControl: ControlWidget {
    static let kind = "HabitControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: HabitControlProvider()) { value in
            ControlWidgetToggle(isOn: value.isDone, action: SetHabitDoneIntent(habit: value.habit)) {
                Label(value.name, systemImage: value.symbol)
            } valueLabel: { isOn in
                Text(isOn ? String(localized: "Done") : String(localized: "Not yet"))
            }
            .tint(value.color)
        }
        .displayName("Check off a habit")
        .description("Check off a habit right from Control Center or the Action button.")
        .promptsForUserConfiguration()
    }
}

@available(iOS 18.0, *)
struct HabitControlProvider: AppIntentControlValueProvider {
    struct Value {
        var habit: HabitControlEntity?
        var name: String
        var symbol: String
        var color: Color
        var isDone: Bool
    }

    func previewValue(configuration: HabitControlConfiguration) -> Value {
        Value(habit: configuration.habit, name: configuration.habit?.name ?? String(localized: "Habit"),
              symbol: "checkmark.circle.fill", color: .accentColor, isDone: false)
    }

    func currentValue(configuration: HabitControlConfiguration) async throws -> Value {
        let data = DataFile.load()
        guard let entity = configuration.habit,
              let habit = data.habits.first(where: { $0.id.uuidString == entity.id }) else {
            return previewValue(configuration: configuration)
        }
        // В Пункте управления только символы SF Symbols, эмодзи заменяем галочкой.
        let symbol: String
        if case .symbol(let name) = habit.icon { symbol = name } else { symbol = "checkmark.circle.fill" }
        return Value(
            habit: entity,
            name: habit.name,
            symbol: symbol,
            color: Palette.color(habit.colorIndex),
            isDone: data.status(habit.id, day: DayKey.make(Date())) == .done
        )
    }
}
