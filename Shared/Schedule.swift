import Foundation

// MARK: - Дни недели

enum Weekdays {
    /// Порядок с понедельника, значения как у Calendar (1 = воскресенье).
    static let ordered: [Int] = [2, 3, 4, 5, 6, 7, 1]
    static let workdays: Set<Int> = [2, 3, 4, 5, 6]
    static let weekend: Set<Int> = [7, 1]
    static let all: Set<Int> = Set(1...7)

    static func short(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "Вс"
        case 2: return "Пн"
        case 3: return "Вт"
        case 4: return "Ср"
        case 5: return "Чт"
        case 6: return "Пт"
        case 7: return "Сб"
        default: return ""
        }
    }
}

// MARK: - Форматирование на русском

enum RuFormat {
    static let locale = Locale(identifier: "ru_RU")

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.calendar = Calendar.app
        f.dateFormat = format
        return f
    }

    private static let dayMonthFormatter = formatter("d MMMM")
    private static let dayMonthYearFormatter = formatter("d MMMM yyyy")
    private static let weekdayDayMonthFormatter = formatter("EEEE, d MMMM")
    private static let monthYearFormatter = formatter("LLLL yyyy")
    private static let shortDateFormatter = formatter("d MMM")

    static func dayMonth(_ date: Date) -> String {
        let cal = Calendar.app
        if cal.component(.year, from: date) != cal.component(.year, from: Date()) {
            dayMonthYearFormatter.timeZone = .current
            return dayMonthYearFormatter.string(from: date)
        }
        dayMonthFormatter.timeZone = .current
        return dayMonthFormatter.string(from: date)
    }

    static func weekdayDayMonth(_ date: Date) -> String {
        weekdayDayMonthFormatter.timeZone = .current
        return weekdayDayMonthFormatter.string(from: date).capitalizedFirst
    }

    static func monthYear(_ date: Date) -> String {
        monthYearFormatter.timeZone = .current
        return monthYearFormatter.string(from: date).capitalizedFirst
    }

    static func shortDate(_ date: Date) -> String {
        shortDateFormatter.timeZone = .current
        return shortDateFormatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    static func weekdayShort(_ date: Date) -> String {
        Weekdays.short(Calendar.app.component(.weekday, from: date))
    }

    /// Человеческое описание дня: "Сегодня", "Вчера", "Завтра" или дата.
    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.app
        if cal.isDateInToday(date) { return "Сегодня" }
        if cal.isDateInYesterday(date) { return "Вчера" }
        if cal.isDateInTomorrow(date) { return "Завтра" }
        return weekdayDayMonth(date)
    }
}

enum RuPlural {
    static func form(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n10 = abs(n) % 10
        let n100 = abs(n) % 100
        if n10 == 1 && n100 != 11 { return one }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
        return many
    }

    static func days(_ n: Int) -> String { "\(n) " + form(n, "день", "дня", "дней") }
    static func habits(_ n: Int) -> String { "\(n) " + form(n, "привычка", "привычки", "привычек") }
    static func times(_ n: Int) -> String { "\(n) " + form(n, "раз", "раза", "раз") }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

// MARK: - Расписание привычки

extension Habit {
    func isScheduled(on date: Date, calendar: Calendar = .app) -> Bool {
        let day = calendar.startOfDay(for: date)
        switch schedule.kind {
        case .once:
            return calendar.isDate(day, inSameDayAs: schedule.onceDate)
        case .repeating:
            if day < calendar.startOfDay(for: schedule.startDate) { return false }
            if let end = schedule.endDate, day > calendar.startOfDay(for: end) { return false }
            return schedule.weekdays.contains(calendar.component(.weekday, from: day))
        }
    }

    /// Первый день, с которого действует привычка.
    func firstDay(calendar: Calendar = .app) -> Date {
        switch schedule.kind {
        case .once: return calendar.startOfDay(for: schedule.onceDate)
        case .repeating: return calendar.startOfDay(for: schedule.startDate)
        }
    }

    /// Последний день действия или nil, если привычка бессрочная.
    func lastDay(calendar: Calendar = .app) -> Date? {
        switch schedule.kind {
        case .once: return calendar.startOfDay(for: schedule.onceDate)
        case .repeating: return schedule.endDate.map { calendar.startOfDay(for: $0) }
        }
    }

    /// Привычка уже закончилась (разовая в прошлом или вышел срок).
    func hasEnded(now: Date = Date(), calendar: Calendar = .app) -> Bool {
        guard let last = lastDay(calendar: calendar) else { return false }
        return last < calendar.startOfDay(for: now)
    }

    var scheduleSummary: String {
        switch schedule.kind {
        case .once:
            return "Один раз, " + RuFormat.dayMonth(schedule.onceDate)
        case .repeating:
            var text: String
            let days = schedule.weekdays
            if days == Weekdays.all {
                text = "Каждый день"
            } else if days == Weekdays.workdays {
                text = "По будням"
            } else if days == Weekdays.weekend {
                text = "По выходным"
            } else {
                text = Weekdays.ordered.filter { days.contains($0) }.map(Weekdays.short).joined(separator: ", ")
            }
            let cal = Calendar.app
            let today = cal.startOfDay(for: Date())
            if cal.startOfDay(for: schedule.startDate) > today {
                text += ", с " + RuFormat.dayMonth(schedule.startDate)
            }
            if let end = schedule.endDate {
                text += ", до " + RuFormat.dayMonth(end)
            }
            return text
        }
    }
}
