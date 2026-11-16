import ActivityKit
import Foundation

/// Live Activity таймера привычки: экран блокировки и Dynamic Island.
/// Общий код: приложение запускает активность, а показывает её расширение виджетов.
struct HabitTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var start: Date
        var end: Date
    }

    let habitID: String
    let name: String
    let icon: HabitIcon
    let colorIndex: Int
}
