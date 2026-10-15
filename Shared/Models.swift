import Foundation

// MARK: - Календарь и ключи дней

extension Calendar {
    /// Календарь приложения: григорианский, неделя начинается с понедельника.
    static var app: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.firstWeekday = 2
        calendar.timeZone = .current
        return calendar
    }
}

/// Ключ дня в формате yyyy-MM-dd в локальном часовом поясе.
enum DayKey {
    static func make(_ date: Date, calendar: Calendar = .app) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(_ key: String, calendar: Calendar = .app) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

// MARK: - Иконка

enum HabitIcon: Codable, Hashable {
    case symbol(String)
    case emoji(String)
}

// MARK: - Время напоминания

struct ReminderTime: Codable, Hashable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(date: Date, calendar: Calendar = .app) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        hour = c.hour ?? 9
        minute = c.minute ?? 0
    }

    var minutesOfDay: Int { hour * 60 + minute }

    var text: String { String(format: "%02d:%02d", hour, minute) }

    func date(on day: Date, calendar: Calendar = .app) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    /// Сегодняшняя дата с этим временем, удобно для DatePicker.
    var dateToday: Date { date(on: Date()) ?? Date() }
}

// MARK: - Расписание

struct HabitSchedule: Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case repeating
        case once
    }

    var kind: Kind
    /// Дни недели по Calendar: 1 = воскресенье ... 7 = суббота.
    var weekdays: Set<Int>
    var startDate: Date
    var endDate: Date?
    var onceDate: Date

    init(kind: Kind = .repeating,
         weekdays: Set<Int> = Set(1...7),
         startDate: Date = Calendar.app.startOfDay(for: Date()),
         endDate: Date? = nil,
         onceDate: Date = Calendar.app.startOfDay(for: Date())) {
        self.kind = kind
        self.weekdays = weekdays
        self.startDate = startDate
        self.endDate = endDate
        self.onceDate = onceDate
    }

    enum CodingKeys: String, CodingKey {
        case kind, weekdays, startDate, endDate, onceDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let today = Calendar.app.startOfDay(for: Date())
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .repeating
        weekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? Set(1...7)
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate) ?? today
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        onceDate = try c.decodeIfPresent(Date.self, forKey: .onceDate) ?? today
    }
}

// MARK: - Привычка

struct Habit: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var details: String
    var icon: HabitIcon
    var colorIndex: Int
    var groupID: UUID?
    var schedule: HabitSchedule
    var reminder: ReminderTime?
    var createdAt: Date
    var isArchived: Bool
    var sortOrder: Int

    init(id: UUID = UUID(),
         name: String = "",
         details: String = "",
         icon: HabitIcon = .symbol("star.fill"),
         colorIndex: Int = 0,
         groupID: UUID? = nil,
         schedule: HabitSchedule = HabitSchedule(),
         reminder: ReminderTime? = ReminderTime(hour: 9, minute: 0),
         createdAt: Date = Date(),
         isArchived: Bool = false,
         sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.details = details
        self.icon = icon
        self.colorIndex = colorIndex
        self.groupID = groupID
        self.schedule = schedule
        self.reminder = reminder
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case id, name, details, icon, colorIndex, groupID, schedule, reminder, createdAt, isArchived, sortOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        details = try c.decodeIfPresent(String.self, forKey: .details) ?? ""
        icon = (try? c.decodeIfPresent(HabitIcon.self, forKey: .icon)) ?? .symbol("star.fill")
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
        schedule = try c.decodeIfPresent(HabitSchedule.self, forKey: .schedule) ?? HabitSchedule()
        reminder = try c.decodeIfPresent(ReminderTime.self, forKey: .reminder)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }
}

// MARK: - Группа

struct HabitGroup: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var sortOrder: Int = 0
}

// MARK: - Отметка

enum CheckStatus: String, Codable, Hashable {
    case done
    case skipped
}

struct CheckIn: Codable, Hashable {
    var status: CheckStatus?
    var note: String?
    var updatedAt: Date
}

struct NoteEntry: Identifiable, Hashable {
    let day: String
    let note: String
    var id: String { day }
}

// MARK: - Настройки

struct AppSettings: Codable, Hashable {
    /// Сколько раз повторить напоминание, если привычка не отмечена.
    var repeatCount: Int = 8
    /// Интервал между повторами, в минутах.
    var repeatIntervalMinutes: Int = 15

    init() {}

    enum CodingKeys: String, CodingKey {
        case repeatCount, repeatIntervalMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        repeatCount = try c.decodeIfPresent(Int.self, forKey: .repeatCount) ?? 8
        repeatIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .repeatIntervalMinutes) ?? 15
    }
}

// MARK: - Все данные приложения

struct AppData: Codable {
    var version: Int = 1
    var habits: [Habit] = []
    var groups: [HabitGroup] = []
    /// Ключ: "<habitID>|yyyy-MM-dd".
    var checkIns: [String: CheckIn] = [:]
    var settings: AppSettings = AppSettings()

    init() {}

    enum CodingKeys: String, CodingKey {
        case version, habits, groups, checkIns, settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        habits = try c.decodeIfPresent([Habit].self, forKey: .habits) ?? []
        groups = try c.decodeIfPresent([HabitGroup].self, forKey: .groups) ?? []
        checkIns = try c.decodeIfPresent([String: CheckIn].self, forKey: .checkIns) ?? [:]
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
    }
}

extension AppData {
    static func key(_ habitID: UUID, _ day: String) -> String {
        habitID.uuidString + "|" + day
    }

    func checkIn(_ habitID: UUID, day: String) -> CheckIn? {
        checkIns[Self.key(habitID, day)]
    }

    func status(_ habitID: UUID, day: String) -> CheckStatus? {
        checkIn(habitID, day: day)?.status
    }

    func note(_ habitID: UUID, day: String) -> String {
        checkIn(habitID, day: day)?.note ?? ""
    }

    mutating func setStatus(_ status: CheckStatus?, habitID: UUID, day: String) {
        let k = Self.key(habitID, day)
        var entry = checkIns[k] ?? CheckIn(status: nil, note: nil, updatedAt: Date())
        entry.status = status
        entry.updatedAt = Date()
        store(entry, key: k)
    }

    mutating func setNote(_ note: String, habitID: UUID, day: String) {
        let k = Self.key(habitID, day)
        var entry = checkIns[k] ?? CheckIn(status: nil, note: nil, updatedAt: Date())
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = trimmed.isEmpty ? nil : trimmed
        entry.updatedAt = Date()
        store(entry, key: k)
    }

    /// Переключает отметку "выполнено". Возвращает true, если привычка стала выполненной.
    @discardableResult
    mutating func toggleDone(habitID: UUID, day: String) -> Bool {
        let wasDone = status(habitID, day: day) == .done
        setStatus(wasDone ? nil : .done, habitID: habitID, day: day)
        return !wasDone
    }

    private mutating func store(_ entry: CheckIn, key: String) {
        let hasNote = !(entry.note ?? "").isEmpty
        if entry.status == nil && !hasNote {
            checkIns[key] = nil
        } else {
            checkIns[key] = entry
        }
    }

    mutating func removeCheckIns(for habitID: UUID) {
        let prefix = habitID.uuidString + "|"
        checkIns = checkIns.filter { !$0.key.hasPrefix(prefix) }
    }

    /// Все отметки привычки с заметками, от новых к старым.
    func notes(for habitID: UUID) -> [NoteEntry] {
        let prefix = habitID.uuidString + "|"
        return checkIns
            .filter { $0.key.hasPrefix(prefix) && !($0.value.note ?? "").isEmpty }
            .map { NoteEntry(day: String($0.key.dropFirst(prefix.count)), note: $0.value.note ?? "") }
            .sorted { $0.day > $1.day }
    }

    var activeHabits: [Habit] {
        habits.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var archivedHabits: [Habit] {
        habits.filter { $0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedGroups: [HabitGroup] {
        groups.sorted { $0.sortOrder < $1.sortOrder }
    }

    func habits(on date: Date, calendar: Calendar = .app) -> [Habit] {
        activeHabits.filter { $0.isScheduled(on: date, calendar: calendar) }
    }

    func group(_ id: UUID?) -> HabitGroup? {
        guard let id else { return nil }
        return groups.first { $0.id == id }
    }
}
