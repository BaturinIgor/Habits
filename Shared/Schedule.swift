import Foundation

// MARK: - Дни недели

enum Weekdays {
    /// Порядок с первого дня недели по региону пользователя, значения как у Calendar (1 = воскресенье).
    static var ordered: [Int] {
        let first = Calendar.app.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }
    static let workdays: Set<Int> = [2, 3, 4, 5, 6]
    static let weekend: Set<Int> = [7, 1]
    static let all: Set<Int> = Set(1...7)

    static func short(_ weekday: Int) -> String {
        let symbols = Calendar.app.shortStandaloneWeekdaySymbols
        guard (1...symbols.count).contains(weekday) else { return "" }
        return symbols[weekday - 1].replacingOccurrences(of: ".", with: "").capitalizedFirst
    }
}

// MARK: - Форматирование по языку системы

enum Fmt {
    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.calendar = Calendar.app
        f.timeZone = .current
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    static func dayMonth(_ date: Date) -> String {
        let cal = Calendar.app
        let otherYear = cal.component(.year, from: date) != cal.component(.year, from: Date())
        return formatter(otherYear ? "dMMMMyyyy" : "dMMMM").string(from: date)
    }

    static func weekdayDayMonth(_ date: Date) -> String {
        formatter("EEEEdMMMM").string(from: date).capitalizedFirst
    }

    static func monthYear(_ date: Date) -> String {
        formatter("LLLLyyyy").string(from: date).capitalizedFirst
    }

    static func shortDate(_ date: Date) -> String {
        formatter("dMMM").string(from: date)
    }

    static func weekdayShort(_ date: Date) -> String {
        Weekdays.short(Calendar.app.component(.weekday, from: date))
    }

    static func time(_ time: ReminderTime) -> String {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: time.dateToday)
    }

    /// "Сегодня", "Вчера", "Завтра" или дата.
    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.app
        if cal.isDateInToday(date) { return String(localized: "Today") }
        if cal.isDateInYesterday(date) { return String(localized: "Yesterday") }
        if cal.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
        return weekdayDayMonth(date)
    }

    static func days(_ n: Int) -> String { String(localized: "\(n) days") }
    static func habitsLeft(_ n: Int) -> String { String(localized: "\(n) habits left") }
    static func habitsPlanned(_ n: Int) -> String { String(localized: "\(n) habits planned") }
    static func weeks(_ n: Int) -> String { String(localized: "\(n) weeks") }
    static func timesPerWeek(_ n: Int) -> String { String(localized: "\(n) times a week") }
    static func repeats(_ count: Int, every minutes: Int) -> String {
        String(localized: "\(count) repeats every \(minutes) min")
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

// MARK: - Порядок показа

extension Array where Element == Habit {
    /// Сначала привычки с напоминанием, по времени от утра к вечеру,
    /// затем привычки без напоминания в ручном порядке.
    func sortedForDisplay() -> [Habit] {
        sorted { a, b in
            switch (a.reminder, b.reminder) {
            case let (ra?, rb?):
                if ra.minutesOfDay != rb.minutesOfDay { return ra.minutesOfDay < rb.minutesOfDay }
                return a.sortOrder < b.sortOrder
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return a.sortOrder < b.sortOrder
            }
        }
    }
}

// MARK: - Расписание привычки

extension Habit {
    /// На паузе ли привычка в этот день.
    func isPaused(on date: Date, calendar: Calendar = .app) -> Bool {
        guard let from = pausedFrom, let until = pausedUntil else { return false }
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: from) && day <= calendar.startOfDay(for: until)
    }

    func isScheduled(on date: Date, calendar: Calendar = .app) -> Bool {
        let day = calendar.startOfDay(for: date)
        if isPaused(on: day, calendar: calendar) { return false }
        switch schedule.kind {
        case .once:
            return calendar.isDate(day, inSameDayAs: schedule.onceDate)
        case .repeating, .weekly:
            if day < calendar.startOfDay(for: schedule.startDate) { return false }
            if let end = schedule.endDate, day > calendar.startOfDay(for: end) { return false }
            if schedule.kind == .weekly { return true }
            return schedule.weekdays.contains(calendar.component(.weekday, from: day))
        }
    }

    /// Первый день, с которого действует привычка.
    func firstDay(calendar: Calendar = .app) -> Date {
        switch schedule.kind {
        case .once: return calendar.startOfDay(for: schedule.onceDate)
        case .repeating, .weekly: return calendar.startOfDay(for: schedule.startDate)
        }
    }

    /// Последний день действия или nil, если привычка бессрочная.
    func lastDay(calendar: Calendar = .app) -> Date? {
        switch schedule.kind {
        case .once: return calendar.startOfDay(for: schedule.onceDate)
        case .repeating, .weekly: return schedule.endDate.map { calendar.startOfDay(for: $0) }
        }
    }

    /// Привычка уже закончилась (разовая в прошлом или вышел срок).
    func hasEnded(now: Date = Date(), calendar: Calendar = .app) -> Bool {
        guard let last = lastDay(calendar: calendar) else { return false }
        return last < calendar.startOfDay(for: now)
    }

    var scheduleSummary: String {
        var text: String
        switch schedule.kind {
        case .once:
            return String(localized: "Once, \(Fmt.dayMonth(schedule.onceDate))")
        case .weekly:
            text = Fmt.timesPerWeek(schedule.timesPerWeek)
        case .repeating:
            let days = schedule.weekdays
            if days == Weekdays.all {
                text = String(localized: "Every day")
            } else if days == Weekdays.workdays {
                text = String(localized: "On weekdays")
            } else if days == Weekdays.weekend {
                text = String(localized: "On weekends")
            } else {
                text = Weekdays.ordered.filter { days.contains($0) }.map(Weekdays.short).joined(separator: ", ")
            }
        }
        let cal = Calendar.app
        let today = cal.startOfDay(for: Date())
        if cal.startOfDay(for: schedule.startDate) > today {
            text += ", " + String(localized: "from \(Fmt.dayMonth(schedule.startDate))")
        }
        if let end = schedule.endDate {
            text += ", " + String(localized: "until \(Fmt.dayMonth(end))")
        }
        return text
    }
}

// MARK: - Секции главного экрана

struct HabitSection: Identifiable {
    let id: String
    let title: String
    let habits: [Habit]
}

/// Секции главного экрана: по частям дня или один список по времени.
func todaySections(_ habits: [Habit], data: AppData, day: String) -> [HabitSection] {
    func finish(_ items: [Habit]) -> [Habit] {
        guard data.settings.doneToBottom else { return items }
        let open = items.filter { data.status($0.id, day: day) == nil }
        let closed = items.filter { data.status($0.id, day: day) != nil }
        return open + closed
    }
    switch data.settings.homeLayout {
    case .byTime:
        return [HabitSection(id: "all", title: "", habits: finish(habits.sortedForDisplay()))]
    case .partsOfDay:
        return PartOfDay.allCases.compactMap { part in
            let items = habits.filter { $0.effectivePartOfDay == part }.sorted { $0.sortOrder < $1.sortOrder }
            return items.isEmpty ? nil : HabitSection(id: part.rawValue, title: part.title, habits: finish(items))
        }
    }
}

/// Разбивает привычки по группам в порядке групп, без группы в конце.
func makeSections(_ habits: [Habit], data: AppData) -> [HabitSection] {
    var result: [HabitSection] = []
    var used = Set<UUID>()
    for group in data.sortedGroups {
        let items = habits.filter { $0.groupID == group.id }
        guard !items.isEmpty else { continue }
        items.forEach { used.insert($0.id) }
        result.append(HabitSection(id: group.id.uuidString, title: group.name, habits: items))
    }
    let rest = habits.filter { !used.contains($0.id) }
    if !rest.isEmpty {
        result.append(HabitSection(id: "ungrouped", title: String(localized: "No group"), habits: rest))
    }
    return result
}
