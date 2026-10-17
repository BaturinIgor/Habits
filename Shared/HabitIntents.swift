import AppIntents
import Foundation
import WidgetKit

/// Отметка привычки прямо из виджета.
struct ToggleHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark habit"
    static let isDiscoverable: Bool = false

    @Parameter(title: "Habit")
    var habitID: String

    @Parameter(title: "Day")
    var day: String

    init() {}

    init(habitID: UUID, day: String) {
        self.habitID = habitID.uuidString
        self.day = day
    }

    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: habitID),
              var data = DataFile.loadIfAvailable() else {
            return .result()
        }
        data.tap(habitID: uuid, day: day)
        DataFile.save(data)
        WidgetCenter.shared.reloadAllTimelines()
        await NotificationPlanner.clearDelivered(habitID: uuid, day: day)
        await NotificationPlanner.reschedule(data: data)
        return .result()
    }
}
