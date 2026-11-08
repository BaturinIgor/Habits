import Foundation

/// Разбор фразы вроде "Таблетки собаке раз в месяц 15 числа в 9 утра"
/// или "Water the plants every other day at 7 pm" в черновик привычки.
/// Понимает русский и английский. Если периодичность или время не найдены,
/// остаются значения по умолчанию, а вся фраза становится названием.
struct VoiceHabit: Equatable {
    var name: String
    var schedule: HabitSchedule
    var reminder: ReminderTime?
    /// В фразе была периодичность или дата.
    var hasSchedule: Bool
}

enum VoiceHabitParser {
    static func parse(_ phrase: String, now: Date = Date(), calendar: Calendar = .app) -> VoiceHabit {
        var parser = Parser(text: " " + phrase.lowercased() + " ", now: now, calendar: calendar)
        parser.run()
        let name = cleanName(parser.text, original: phrase)
        return VoiceHabit(name: name, schedule: parser.schedule, reminder: parser.reminder, hasSchedule: parser.hasSchedule)
    }

    // MARK: Название

    private static let fillers = [
        "напомни мне", "напоминай мне", "напомни", "напоминай", "добавь привычку", "новая привычка",
        "создай привычку", "добавь напоминание", "создай напоминание", "добавь", "мне надо", "мне нужно", "нужно", "надо",
        "remind me to", "remind me", "add a habit", "add habit", "new habit", "create a habit", "add a reminder", "add",
        "i need to", "i have to",
    ]

    private static func cleanName(_ rest: String, original: String) -> String {
        var text = " " + rest + " "
        for filler in fillers {
            text = text.replacingOccurrences(of: " \(filler) ", with: " ")
        }
        // Предлоги, повисшие после удаления времени и даты.
        let dangling: Set<String> = ["в", "во", "на", "по", "и", "at", "on", "in", "and", "every", "each", "каждый", "каждую", "каждое", "каждые"]
        var words = text.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
        while let last = words.last, dangling.contains(last) { words.removeLast() }
        while let first = words.first, dangling.contains(first) { words.removeFirst() }
        var name = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " .,!?-"))
        if name.isEmpty {
            name = original.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return name.capitalizedFirst
    }
}

// MARK: - Разбор

private struct Parser {
    var text: String
    let now: Date
    let calendar: Calendar
    var schedule = HabitSchedule()
    var reminder: ReminderTime?
    var hasSchedule = false

    private var today: Date { calendar.startOfDay(for: now) }

    mutating func run() {
        // Сначала периодичность и даты, чтобы "раз в 3 дня" или "в 5 марта" не приняли за время.
        if parseEveryOtherDay() || parseEveryNDays() || parseTimesPerWeek() || parseMonthly() || parseYearly()
            || parseWeekdays() || parseDaily() || parseOnce() {
            hasSchedule = true
        }
        parseTime()
    }

    // MARK: Регулярные выражения

    /// Находит первое совпадение, вырезает его из текста и возвращает группы.
    private mutating func take(_ pattern: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var groups: [String?] = []
        for i in 0..<match.numberOfRanges {
            let range = match.range(at: i)
            groups.append(range.location == NSNotFound ? nil : ns.substring(with: range))
        }
        text = ns.replacingCharacters(in: match.range, with: " ")
        return groups
    }

    private func has(_ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    // MARK: Время

    private mutating func parseTime() {
        // "в 9", "в 9:30", "в 21.00", "в 9 утра", "at 7 pm", "at 7:30am"
        let pattern = #"\s(?:в|во|к|at)\s+(\d{1,2})(?:[:.](\d{2}))?\s*(утра|вечера|дня|ночи|часов|часа|час|am|pm|a\.m\.|p\.m\.)?(?=[\s,.!?])"#
        if let g = take(pattern), let hour = Int(g[1] ?? "") {
            setTime(hour: hour, minute: Int(g[2] ?? "") ?? 0, suffix: g[3])
            return
        }
        // "9 утра", "7 pm", "19:30" без предлога
        if let g = take(#"\s(\d{1,2})(?:[:.](\d{2}))?\s*(утра|вечера|ночи|am|pm|a\.m\.|p\.m\.)(?=[\s,.!?])"#),
           let hour = Int(g[1] ?? "") {
            setTime(hour: hour, minute: Int(g[2] ?? "") ?? 0, suffix: g[3])
            return
        }
        if let g = take(#"\s(\d{1,2})[:.](\d{2})(?=[\s,.!?])"#), let hour = Int(g[1] ?? "") {
            setTime(hour: hour, minute: Int(g[2] ?? "") ?? 0, suffix: nil)
            return
        }
        if take(#"\s(?:утром|in the morning)(?=[\s,.!?])"#) != nil { reminder = ReminderTime(hour: 9, minute: 0) }
        else if take(#"\s(?:вечером|in the evening|tonight)(?=[\s,.!?])"#) != nil { reminder = ReminderTime(hour: 20, minute: 0) }
        else if take(#"\s(?:днём|днем|in the afternoon)(?=[\s,.!?])"#) != nil { reminder = ReminderTime(hour: 14, minute: 0) }
    }

    private mutating func setTime(hour rawHour: Int, minute: Int, suffix: String?) {
        var hour = rawHour
        switch suffix {
        case "вечера", "pm", "p.m.":
            if hour < 12 { hour += 12 }
        case "дня":
            if hour < 12 && hour <= 6 { hour += 12 }
        case "ночи", "am", "a.m.":
            if hour == 12 { hour = 0 }
        default:
            break
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return }
        reminder = ReminderTime(hour: hour, minute: minute)
    }

    // MARK: Периодичность

    private mutating func parseEveryOtherDay() -> Bool {
        guard take(#"\s(?:через день|каждый второй день|every other day|every second day)(?=[\s,.!?])"#) != nil else { return false }
        schedule.kind = .everyNDays
        schedule.intervalDays = 2
        return true
    }

    private mutating func parseEveryNDays() -> Bool {
        let pattern = #"\s(?:раз в|каждые|every)\s+(\d{1,2})\s+(?:дня|дней|день|days)(?=[\s,.!?])"#
        guard let g = take(pattern), let n = Int(g[1] ?? ""), n >= 1 else { return false }
        if n == 1 {
            schedule.kind = .repeating
            schedule.weekdays = Weekdays.all
        } else {
            schedule.kind = .everyNDays
            schedule.intervalDays = min(n, 90)
        }
        return true
    }

    private mutating func parseTimesPerWeek() -> Bool {
        let pattern = #"\s(\d)\s+(?:раза|раз)\s+в\s+неделю|\s(\d)\s+times\s+(?:a|per)\s+week"#
        guard let g = take(pattern), let n = Int(g[1] ?? g[2] ?? ""), (1...6).contains(n) else { return false }
        schedule.kind = .weekly
        schedule.timesPerWeek = n
        return true
    }

    private mutating func parseMonthly() -> Bool {
        let pattern = #"\s(?:раз в месяц|каждый месяц|ежемесячно|every month|once a month|monthly)(?=[\s,.!?])"#
        guard take(pattern) != nil else { return false }
        schedule.kind = .monthly
        var day = calendar.component(.day, from: today)
        if let g = take(#"\s(\d{1,2})(?:-?го|-?е)?\s+числа(?=[\s,.!?])|\s(\d{1,2})-?го(?=[\s,.!?])|\son the (\d{1,2})(?:st|nd|rd|th)?(?=[\s,.!?])"#),
           let n = Int(g[1] ?? g[2] ?? g[3] ?? ""), (1...31).contains(n) {
            day = n
        }
        schedule.startDate = nextDate(day: day, month: nil)
        return true
    }

    private mutating func parseYearly() -> Bool {
        let pattern = #"\s(?:раз в год|каждый год|ежегодно|every year|once a year|yearly|annually)(?=[\s,.!?])"#
        let yearly = take(pattern) != nil
        let birthday = has(#"день рождения|birthday"#)
        if let dayMonth = takeDayMonth() {
            let (day, month) = dayMonth
            if yearly || birthday {
                schedule.kind = .yearly
                schedule.startDate = nextDate(day: day, month: month)
            } else {
                schedule.kind = .once
                schedule.onceDate = nextDate(day: day, month: month)
            }
            return true
        }
        guard yearly else { return false }
        schedule.kind = .yearly
        schedule.startDate = today
        return true
    }

    private mutating func parseWeekdays() -> Bool {
        var days = Set<Int>()
        if take(#"\s(?:по будням|в будни|on weekdays|every weekday|on workdays)(?=[\s,.!?])"#) != nil {
            days.formUnion(Weekdays.workdays)
        }
        if take(#"\s(?:по выходным|в выходные|on weekends|every weekend)(?=[\s,.!?])"#) != nil {
            days.formUnion(Weekdays.weekend)
        }
        // Calendar: 1 = воскресенье.
        let names: [(Int, String)] = [
            (2, #"понедельник(?:ам|а|у)?|mondays?"#),
            (3, #"вторник(?:ам|а|у)?|tuesdays?"#),
            (4, #"сред(?:ам|у|а|ы)|wednesdays?"#),
            (5, #"четверг(?:ам|а|у)?|thursdays?"#),
            (6, #"пятниц(?:ам|у|а|ы)|fridays?"#),
            (7, #"суббот(?:ам|у|а|ы)|saturdays?"#),
            (1, #"воскресень(?:ям|е|я|ю)|sundays?"#),
        ]
        for (weekday, word) in names {
            // "по понедельникам", "в среду", "и в пятницу", "on mondays", "every friday", "and friday"
            while take(#"\s(?:(?:по|в|во|on|every|each|и|and|,)\s+)?(?:"# + word + #")(?=[\s,.!?])"#) != nil {
                days.insert(weekday)
            }
        }
        let onceAWeek = take(#"\s(?:раз в неделю|каждую неделю|еженедельно|every week|once a week|weekly)(?=[\s,.!?])"#) != nil
        if days.isEmpty && onceAWeek {
            days.insert(calendar.component(.weekday, from: today))
        }
        guard !days.isEmpty else { return false }
        _ = take(#"\s(?:каждый|каждую|каждое)(?=[\s,.!?])"#)
        schedule.kind = .repeating
        schedule.weekdays = days
        return true
    }

    private mutating func parseDaily() -> Bool {
        guard take(#"\s(?:каждый день|ежедневно|every day|everyday|daily)(?=[\s,.!?])"#) != nil else { return false }
        schedule.kind = .repeating
        schedule.weekdays = Weekdays.all
        return true
    }

    private mutating func parseOnce() -> Bool {
        let options: [(String, Int)] = [
            (#"\s(?:послезавтра|the day after tomorrow)(?=[\s,.!?])"#, 2),
            (#"\s(?:завтра|tomorrow)(?=[\s,.!?])"#, 1),
            (#"\s(?:сегодня|today)(?=[\s,.!?])"#, 0),
        ]
        for (pattern, offset) in options where take(pattern) != nil {
            schedule.kind = .once
            schedule.onceDate = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return true
        }
        return false
    }

    // MARK: Даты

    private static let ruMonths = ["январ", "феврал", "март", "апрел", "ма", "июн", "июл", "август", "сентябр", "октябр", "ноябр", "декабр"]
    private static let enMonths = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]

    /// "15 марта", "15-го марта", "march 15", "15 march", "on march 15th".
    private mutating func takeDayMonth() -> (Int, Int)? {
        for (index, stem) in Self.ruMonths.enumerated() {
            let ending = stem == "ма" ? "я|й|е" : "я|а|е|ь"
            if let g = take(#"\s(?:на\s+)?(\d{1,2})(?:-?го|-?е)?\s+"# + stem + "(?:" + ending + #")(?=[\s,.!?])"#),
               let day = Int(g[1] ?? ""), (1...31).contains(day) {
                return (day, index + 1)
            }
        }
        for (index, month) in Self.enMonths.enumerated() {
            let short = String(month.prefix(3))
            let name = "(?:\(month)|\(short))"
            if let g = take(#"\s(?:on\s+)?(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?(?:\s+of)?\s+"# + name + #"(?=[\s,.!?])"#),
               let day = Int(g[1] ?? ""), (1...31).contains(day) {
                return (day, index + 1)
            }
            if let g = take(#"\s(?:on\s+)?"# + name + #"\s+(\d{1,2})(?:st|nd|rd|th)?(?=[\s,.!?])"#),
               let day = Int(g[1] ?? ""), (1...31).contains(day) {
                return (day, index + 1)
            }
        }
        return nil
    }

    /// Ближайшая дата (сегодня или позже) с этим числом и, если задан, месяцем.
    /// Если в месяце нет такого числа, берётся последний день месяца.
    private func nextDate(day: Int, month: Int?) -> Date {
        let year = calendar.component(.year, from: today)
        let currentMonth = calendar.component(.month, from: today)
        for step in 0..<25 {
            let candidateMonth: Int
            let candidateYear: Int
            if let month {
                candidateMonth = month
                candidateYear = year + step
            } else {
                let total = currentMonth - 1 + step
                candidateMonth = total % 12 + 1
                candidateYear = year + total / 12
            }
            guard let first = calendar.date(from: DateComponents(year: candidateYear, month: candidateMonth, day: 1)),
                  let length = calendar.range(of: .day, in: .month, for: first)?.count,
                  let date = calendar.date(from: DateComponents(year: candidateYear, month: candidateMonth, day: min(day, length)))
            else { continue }
            if date >= today { return date }
            if month != nil && step > 1 { break }
        }
        return today
    }
}
