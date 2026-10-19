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
        if let date = DayKey.date(day) {
            await NotificationPlanner.notifyChain(after: uuid, day: date, data: data)
        }
        return .result()
    }
}

/// Кормление питомца прямо из виджета.
struct FeedPetIntent: AppIntent {
    static let title: LocalizedStringResource = "Feed pet"
    static let isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        guard var data = DataFile.loadIfAvailable(), var pet = data.wallet.pet else { return .result() }
        let key = DayKey.make(Date())
        guard pet.feeds[key, default: 0] < Sparks.feedsPerDay,
              Sparks.snapshotBalance(data) >= Sparks.feedPrice else { return .result() }
        pet.feeds[key, default: 0] += 1
        data.wallet.pet = pet
        data.wallet.spent += Sparks.feedPrice
        DataFile.save(data)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
