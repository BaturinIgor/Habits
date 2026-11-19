import Foundation
import OSLog

// Обмен данными между iPhone и Apple Watch.
// Файл общий для приложения на iPhone, приложения на часах и компликаций.
// iPhone присылает снимок привычек на сегодня и завтра, а часы присылают отметки.

/// Привычка в снимке для часов: только то, что нужно для отметки и показа.
struct WatchHabit: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var emoji: String?
    var symbol: String?
    var colorIndex: Int
    /// Цель на день: больше 1 у количественных привычек.
    var target: Int
    /// Сколько сделано (у выполненной равно цели).
    var count: Int
    var done: Bool
    var skipped: Bool
    /// Длительность таймера в минутах, если она задана.
    var timerMinutes: Int?

    /// Нажатие на привычку, как на iPhone: обычная переключается,
    /// количественная прибавляет 1, а после цели сбрасывается.
    func tapped() -> WatchHabit {
        var next = self
        next.skipped = false
        if target <= 1 {
            next.done = !done
            next.count = next.done ? 1 : 0
        } else if done {
            next.done = false
            next.count = 0
        } else {
            next.count = min(target, count + 1)
            next.done = next.count >= target
        }
        return next
    }

    func applying(_ mark: WatchMark) -> WatchHabit {
        var next = self
        next.done = mark.done
        next.count = mark.done ? max(1, target) : min(mark.count, target)
        next.skipped = false
        return next
    }

    func matches(_ mark: WatchMark) -> Bool {
        done == mark.done && (done || count == mark.count)
    }
}

/// Привычки одного дня.
struct WatchDay: Codable, Hashable {
    /// Ключ дня yyyy-MM-dd в часовом поясе iPhone.
    var day: String
    var habits: [WatchHabit]

    var doneCount: Int { habits.filter(\.done).count }
    /// Пропущенные не считаются: их не нужно делать.
    var plannedCount: Int { habits.filter { !$0.skipped || $0.done }.count }
}

/// Снимок с iPhone.
struct WatchSnapshot: Codable, Hashable {
    var generatedAt: Date
    var isPro: Bool
    /// Сегодня и завтра: так часы показывают правильный день сразу после полуночи.
    var days: [WatchDay]
    /// Отметки с часов, которые iPhone уже получил: ключ отметки и её время (по часам).
    /// iPhone мог отметку и не применить (на нём отметили позже), но ждать её больше не нужно.
    var acks: [String: Date]? = nil

    func day(_ key: String) -> WatchDay? {
        days.first { $0.day == key }
    }
}

/// Отметка с часов: каким привычка должна стать в этот день.
/// Передаётся состояние, а не нажатие, поэтому повторная доставка ничего не портит.
struct WatchMark: Codable, Hashable {
    var habitID: UUID
    var day: String
    var done: Bool
    var count: Int
    /// Когда отметили на часах. Более свежая отметка на iPhone побеждает.
    var at: Date

    var key: String { habitID.uuidString + "|" + day }
}

/// Таймер привычки на часах.
struct WatchTimerRun: Codable, Equatable {
    let habitID: UUID
    let day: String
    let start: Date
    let end: Date
    /// Цель привычки на день: чтобы отметить её, даже если дня уже нет в снимке.
    var target: Int? = nil

    /// Отметка «сделано» по таймеру. Время — конец таймера, а не момент, когда это заметили:
    /// иначе поздняя проверка перебила бы то, что успели поменять на iPhone.
    func completionMark(now: Date) -> WatchMark {
        WatchMark(habitID: habitID, day: day, done: true, count: max(1, target ?? 1), at: min(now, end))
    }
}

/// Всё, что знают часы: последний снимок и отметки, которые iPhone ещё не подтвердил.
/// Его же читают компликации.
struct WatchState: Codable, Hashable {
    var snapshot: WatchSnapshot?
    var pending: [String: WatchMark] = [:]

    /// День с учётом неподтверждённых отметок.
    func day(_ key: String) -> WatchDay? {
        guard var day = snapshot?.day(key) else { return nil }
        day.habits = day.habits.map { habit in
            if let mark = pending[habit.id.uuidString + "|" + key] {
                return habit.applying(mark)
            }
            return habit
        }
        return day
    }

    /// Новый снимок с iPhone: отметки, которые он уже получил или уже учёл, больше не нужны.
    /// Остальные ждут: часы могли быть без связи, и отметка ещё в очереди на доставку.
    mutating func receive(_ fresh: WatchSnapshot) {
        if let old = snapshot, old.generatedAt > fresh.generatedAt { return }
        snapshot = fresh
        let acks = fresh.acks ?? [:]
        let oldest = WatchDayKey.ackHorizon(before: fresh.generatedAt)
        pending = pending.filter { key, mark in
            if let acked = acks[key], acked >= mark.at { return false }
            guard let day = fresh.day(mark.day) else {
                // Дня уже нет в снимке (например, таймер закончился после полуночи):
                // ждём подтверждения, но не дольше нескольких дней.
                return mark.day >= oldest
            }
            guard let habit = day.habits.first(where: { $0.id == mark.habitID }) else {
                // Привычку удалили или убрали из этого дня.
                return false
            }
            return !habit.matches(mark)
        }
    }
}

enum WatchKeys {
    static let snapshot = "snapshot"
    static let mark = "mark"
    static let appGroup = "group.com.personal.habits"
}

/// Ключ дня, как на iPhone: yyyy-MM-dd в местном часовом поясе.
enum WatchDayKey {
    static func make(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Самый старый день, отметки за который ещё ждут подтверждения (и iPhone их помнит).
    static func ackHorizon(before date: Date) -> String {
        make(date.addingTimeInterval(-3 * 86_400))
    }

    static func nextMidnight(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86_400)
    }
}

/// Файл состояния на часах в общей папке приложения и компликаций.
enum WatchStateFile {
    private static let log = Logger(subsystem: "com.personal.habits", category: "WatchState")

    static let url: URL = {
        let fm = FileManager.default
        let base: URL
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: WatchKeys.appGroup) {
            base = group
        } else {
            // Без App Group приложение и компликации пишут в разные папки,
            // и компликация остаётся пустой. Обычно это значит, что не настроена подпись.
            log.error("App Group \(WatchKeys.appGroup, privacy: .public) is unavailable, falling back to Application Support; complications will not see watch data")
            base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        }
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("watch-state.json")
    }()

    static func load() -> WatchState {
        guard let raw = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(WatchState.self, from: raw) else { return WatchState() }
        return state
    }

    static func save(_ state: WatchState) {
        guard let raw = try? JSONEncoder().encode(state) else { return }
        try? raw.write(to: url, options: .atomic)
    }
}
