import AppIntents
import Foundation
import WidgetKit

// Кнопка привычки в Пункте управления, на экране блокировки и на кнопке действия (iOS 18).
// Код общий: кнопка живёт в расширении виджетов, а приложение видит те же типы.

@available(iOS 18.0, *)
struct HabitControlEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static let defaultQuery = HabitControlQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(_ habit: Habit) {
        id = habit.id.uuidString
        name = habit.name
    }
}

@available(iOS 18.0, *)
struct HabitControlQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [HabitControlEntity] {
        DataFile.load().trackedHabits
            .filter { identifiers.contains($0.id.uuidString) }
            .map(HabitControlEntity.init)
    }

    func suggestedEntities() async throws -> [HabitControlEntity] {
        DataFile.load().trackedHabits.map(HabitControlEntity.init)
    }
}

/// Какую привычку показывает кнопка: выбирается при добавлении в Пункт управления.
@available(iOS 18.0, *)
struct HabitControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Habit"

    @Parameter(title: "Habit")
    var habit: HabitControlEntity?

    init() {}
}

/// Нажатие на кнопку: отметить привычку за сегодня или снять отметку.
@available(iOS 18.0, *)
struct SetHabitDoneIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Check off a habit"
    static let isDiscoverable: Bool = false

    @Parameter(title: "Habit")
    var habit: HabitControlEntity?

    @Parameter(title: "Done")
    var value: Bool

    init() {}

    init(habit: HabitControlEntity?) {
        self.habit = habit
    }

    func perform() async throws -> some IntentResult {
        guard let id = habit.flatMap({ UUID(uuidString: $0.id) }),
              var data = DataFile.loadIfAvailable(),
              data.habits.contains(where: { $0.id == id }) else {
            return .result()
        }
        let day = DayKey.make(Date())
        data.setStatus(value ? .done : nil, habitID: id, day: day)
        DataFile.save(data)
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        if value {
            await NotificationPlanner.clearDelivered(habitID: id, day: day)
            if let date = DayKey.date(day) {
                await NotificationPlanner.notifyChain(after: id, day: date, data: data)
            }
        }
        await NotificationPlanner.reschedule(data: data)
        return .result()
    }
}
