import SwiftUI
import WidgetKit

#if DEBUG
/// Макеты экранов часов (design/<версия>/screens): запуск с `-design` показывает демо-данные
/// без iPhone. Только в отладочной сборке.
///   -design-empty                снимка с iPhone нет
///   -design-free                 без Pro (таймер закрыт)
///   -design-done                 всё сделано
///   -design-timer idle|running   сразу открыть таймер медитации
///   -design-complications        все виды компликации на одном экране
enum WatchDesign {
    static let args = ProcessInfo.processInfo.arguments
    static var isOn: Bool { args.contains("-design") }
    static func has(_ flag: String) -> Bool { isOn && args.contains(flag) }
    static func value(_ flag: String) -> String? {
        guard isOn, let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static let meditationID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static var isRussian: Bool { Locale.preferredLanguages.first?.hasPrefix("ru") == true }

    static var state: WatchState? {
        guard isOn else { return nil }
        if has("-design-empty") { return WatchState() }
        let ru = isRussian
        func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
        let all = has("-design-done")
        let habits = [
            WatchHabit(id: id(1), name: ru ? "Утренняя зарядка" : "Morning exercises", symbol: "figure.run",
                       colorIndex: 0, target: 1, count: 1, done: true, skipped: false),
            WatchHabit(id: id(2), name: ru ? "Пить воду" : "Drink water", symbol: "drop.fill",
                       colorIndex: 3, target: 8, count: all ? 8 : 5, done: all, skipped: false),
            WatchHabit(id: id(3), name: ru ? "Медитация" : "Meditation", symbol: "brain.head.profile",
                       colorIndex: 5, target: 1, count: all ? 1 : 0, done: all, skipped: false, timerMinutes: 10),
            WatchHabit(id: id(4), name: ru ? "Прочитать 20 страниц" : "Read 20 pages", symbol: "book.fill",
                       colorIndex: 2, target: 1, count: all ? 1 : 0, done: all, skipped: false),
            WatchHabit(id: id(6), name: ru ? "Пройти 10 000 шагов" : "Walk 10,000 steps", symbol: "figure.walk",
                       colorIndex: 4, target: 1, count: 1, done: true, skipped: false),
        ]
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        let snapshot = WatchSnapshot(
            generatedAt: now,
            isPro: !has("-design-free"),
            days: [WatchDay(day: WatchDayKey.make(now), habits: habits),
                   WatchDay(day: WatchDayKey.make(tomorrow), habits: habits)]
        )
        return WatchState(snapshot: snapshot)
    }

    /// Таймер медитации, идущий 3,5 минуты из 10.
    static var timer: WatchTimerRun? {
        guard value("-design-timer") == "running" else { return nil }
        let start = Date().addingTimeInterval(-210)
        return WatchTimerRun(habitID: meditationID, day: WatchDayKey.make(Date()), start: start,
                             end: start.addingTimeInterval(600), target: 1)
    }

    static var openTimer: UUID? { value("-design-timer") != nil ? meditationID : nil }
}

/// Все виды компликации «Прогресс дня» на демо-данных (3 из 5 и «всё сделано»).
/// Рисуется в приложении, а не на циферблате: подписи угловой компликации (widgetLabel)
/// и тонировка циферблата здесь не видны.
struct WatchComplicationGallery: View {
    private let entry = ProgressEntry(date: Date(), done: 3, total: 5,
                                      next: WatchDesign.isRussian ? "Медитация" : "Meditation", hasData: true)
    private let doneEntry = ProgressEntry(date: Date(), done: 5, total: 5, next: nil, hasData: true)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    circle(entry)
                    circle(doneEntry)
                    ProgressComplicationView(entry: entry, familyOverride: .accessoryCorner)
                        .frame(width: 44, height: 44)
                }
                ProgressComplicationView(entry: entry, familyOverride: .accessoryRectangular)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12)))
                ProgressComplicationView(entry: entry, familyOverride: .accessoryInline)
                    .font(.footnote)
            }
            .padding(.horizontal, 6)
        }
    }

    private func circle(_ entry: ProgressEntry) -> some View {
        ProgressComplicationView(entry: entry, familyOverride: .accessoryCircular)
            .frame(width: 50, height: 50)
            .background(Circle().fill(Color.white.opacity(0.12)))
    }
}
#endif
