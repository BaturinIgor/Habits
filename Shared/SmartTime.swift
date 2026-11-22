import Foundation

/// Умное время напоминания (KAN-135).
///
/// По отметкам за последние три недели считает, во сколько человек обычно отмечает привычку,
/// и предлагает перенести напоминание, если оно стабильно приходит намного раньше или позже.
/// Всё считается на устройстве, без сервера.
///
/// Как считается:
/// 1. Берутся отметки «выполнено», поставленные в тот же день (отметка задним числом ничего не говорит о времени).
///    Время берётся по местным часам в момент отметки (CheckIn.tz), поэтому переезд в другой пояс не сдвигает историю.
/// 2. Редкие выбросы дальше трёх часов от общей медианы отбрасываются (случайная отметка ночью).
/// 3. Медиана по каждому дню недели, потом медиана этих медиан: пять будних дней перевешивают
///    позднюю отметку в выходные, а один день недели с кучей отметок не перетягивает остальные.
/// 4. Предложение есть, только если данных хватает и разница стабильная: у большинства дней недели
///    обычное время в ту же сторону и не меньше чем на `threshold` минут.
enum SmartTime {
    /// Окно истории, дней.
    static let windowDays = 21
    /// Меньше отметок - мало данных, ничего не предлагаем.
    static let minSamples = 6
    /// Минимум разных дней недели с отметками.
    static let minWeekdays = 3
    /// Разница в минутах, начиная с которой напоминание «намного» раньше или позже.
    static let threshold = 45
    /// Напоминание ставим чуть раньше обычного времени отметки.
    static let lead = 10
    /// Отметки дальше этого от общей медианы - выбросы, минут.
    static let outlierLimit = 180
    /// Новое время округляем до 5 минут.
    static let step = 5

    struct Sample: Equatable {
        /// День недели по Calendar: 1 = воскресенье ... 7 = суббота.
        let weekday: Int
        /// Минуты от полуночи по местным часам в момент отметки.
        let minutes: Int
    }

    struct Suggestion: Equatable {
        /// Время напоминания сейчас.
        let current: ReminderTime
        /// Во сколько обычно отмечается привычка.
        let typical: ReminderTime
        /// Новое время напоминания.
        let suggested: ReminderTime

        /// На сколько минут сдвигается напоминание: плюс - позже, минус - раньше.
        var shiftMinutes: Int { suggested.minutesOfDay - current.minutesOfDay }
    }

    /// Привычка подходит для умного времени: есть напоминание и время отметки ставит сам человек
    /// (у Здоровья и слов отметка ставится сама, у «Бросаю» отметок нет).
    static func isEligible(_ habit: Habit) -> Bool {
        habit.reminder != nil && !habit.isArchived && !habit.isQuit && !habit.isWords
            && habit.health == nil && habit.schedule.kind != .once
    }

    /// Отметки «выполнено» за окно до `now` включительно.
    static func samples(for habit: Habit, in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> [Sample] {
        let today = calendar.startOfDay(for: now)
        var result: [Sample] = []
        for offset in 0..<windowDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = DayKey.make(day, calendar: calendar)
            guard let checkIn = data.checkIn(habit.id, day: key), checkIn.status == .done else { continue }
            // Местные часы в момент отметки: пояс из отметки, у старых отметок - текущий.
            var local = calendar
            if let tz = checkIn.tz, let zone = TimeZone(secondsFromGMT: tz) { local.timeZone = zone }
            // Отметка задним числом или после полуночи - не про время привычки.
            guard DayKey.make(checkIn.updatedAt, calendar: local) == key else { continue }
            let parts = local.dateComponents([.hour, .minute], from: checkIn.updatedAt)
            let weekday = calendar.component(.weekday, from: day)
            result.append(Sample(weekday: weekday, minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0)))
        }
        return result
    }

    /// Обычное время отметки в минутах от полуночи или nil, если данных мало.
    static func typicalMinutes(_ samples: [Sample]) -> Int? {
        guard let clean = withoutOutliers(samples) else { return nil }
        return median(Array(weekdayMedians(clean).values))
    }

    /// Предложение перенести напоминание или nil, если переносить не нужно или данных мало.
    static func suggestion(for habit: Habit, in data: AppData, now: Date = Date(), calendar: Calendar = .app) -> Suggestion? {
        guard isEligible(habit), let current = habit.reminder else { return nil }
        return suggestion(current: current, samples: samples(for: habit, in: data, now: now, calendar: calendar))
    }

    static func suggestion(current: ReminderTime, samples: [Sample]) -> Suggestion? {
        guard let clean = withoutOutliers(samples) else { return nil }
        let medians = weekdayMedians(clean)
        guard let typical = median(Array(medians.values)) else { return nil }
        let difference = typical - current.minutesOfDay
        guard abs(difference) >= threshold else { return nil }
        // Стабильно: у двух третей дней недели обычное время в ту же сторону и не меньше порога.
        let sameSide = medians.values.filter { value in
            let d = value - current.minutesOfDay
            return abs(d) >= threshold && (d > 0) == (difference > 0)
        }.count
        guard sameSide * 3 >= medians.count * 2 else { return nil }
        let target = min(max(typical - lead, 0), 23 * 60 + 55)
        let rounded = Int((Double(target) / Double(step)).rounded()) * step
        let suggested = ReminderTime(hour: rounded / 60, minute: rounded % 60)
        guard suggested != current else { return nil }
        return Suggestion(current: current,
                          typical: ReminderTime(hour: typical / 60, minute: typical % 60),
                          suggested: suggested)
    }

    /// Сколько ещё отметок нужно, чтобы появилось предложение.
    static func missingSamples(_ samples: [Sample]) -> Int {
        max(0, minSamples - samples.count)
    }

    // MARK: Медианы

    /// Отметки без выбросов или nil, если после этого данных мало.
    private static func withoutOutliers(_ samples: [Sample]) -> [Sample]? {
        guard samples.count >= minSamples, let center = median(samples.map(\.minutes)) else { return nil }
        let near = samples.filter { abs($0.minutes - center) <= outlierLimit }
        // Выбросы - это редкие отметки (не больше пятой части). Если далеко от медианы много отметок,
        // это не случайность, а другой режим в часть дней: такие оставляем, и проверка стабильности решит.
        let clean = (samples.count - near.count) * 5 <= samples.count ? near : samples
        guard clean.count >= minSamples, Set(clean.map(\.weekday)).count >= minWeekdays else { return nil }
        return clean
    }

    private static func weekdayMedians(_ samples: [Sample]) -> [Int: Int] {
        Dictionary(grouping: samples, by: \.weekday).compactMapValues { median($0.map(\.minutes)) }
    }

    /// Медиана; при чётном числе - среднее двух средних значений.
    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[mid] }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }
}

extension AppData {
    /// Автосдвиг для привычек с включённым «Умным временем». Возвращает сдвинутые привычки и на сколько минут.
    mutating func applySmartTimes(now: Date = Date(), calendar: Calendar = .app) -> [(id: UUID, shift: Int)] {
        var shifted: [(id: UUID, shift: Int)] = []
        for index in habits.indices where habits[index].smartTime == true {
            guard let suggestion = SmartTime.suggestion(for: habits[index], in: self, now: now, calendar: calendar) else { continue }
            habits[index].reminder = suggestion.suggested
            shifted.append((habits[index].id, suggestion.shiftMinutes))
        }
        return shifted
    }
}
