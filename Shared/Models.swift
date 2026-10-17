import Foundation

// MARK: - Календарь и ключи дней

extension Calendar {
    /// Календарь приложения: григорианский, язык и первый день недели по настройкам пользователя.
    static var app: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        calendar.firstWeekday = Calendar.current.firstWeekday
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

    var text: String { Fmt.time(self) }

    func date(on day: Date, calendar: Calendar = .app) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    /// Сегодняшняя дата с этим временем, удобно для DatePicker.
    var dateToday: Date { date(on: Date()) ?? Date() }
}

// MARK: - Часть дня

enum PartOfDay: String, Codable, Hashable, CaseIterable, Identifiable {
    case morning
    case afternoon
    case evening
    case anytime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return String(localized: "Morning")
        case .afternoon: return String(localized: "Afternoon")
        case .evening: return String(localized: "Evening")
        case .anytime: return String(localized: "Anytime")
        }
    }

    /// Часть дня по времени напоминания: утро до 12, день до 17, дальше вечер.
    init(time: ReminderTime) {
        switch time.hour {
        case 4..<12: self = .morning
        case 12..<17: self = .afternoon
        default: self = .evening
        }
    }
}

// MARK: - Расписание

struct HabitSchedule: Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case repeating
        case weekly
        case once
    }

    var kind: Kind
    /// Дни недели по Calendar: 1 = воскресенье ... 7 = суббота.
    var weekdays: Set<Int>
    var startDate: Date
    var endDate: Date?
    var onceDate: Date
    /// Для вида "N раз в неделю".
    var timesPerWeek: Int

    init(kind: Kind = .repeating,
         weekdays: Set<Int> = Set(1...7),
         startDate: Date = Calendar.app.startOfDay(for: Date()),
         endDate: Date? = nil,
         onceDate: Date = Calendar.app.startOfDay(for: Date()),
         timesPerWeek: Int = 3) {
        self.kind = kind
        self.weekdays = weekdays
        self.startDate = startDate
        self.endDate = endDate
        self.onceDate = onceDate
        self.timesPerWeek = timesPerWeek
    }

    enum CodingKeys: String, CodingKey {
        case kind, weekdays, startDate, endDate, onceDate, timesPerWeek
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let today = Calendar.app.startOfDay(for: Date())
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .repeating
        weekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? Set(1...7)
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate) ?? today
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        onceDate = try c.decodeIfPresent(Date.self, forKey: .onceDate) ?? today
        timesPerWeek = try c.decodeIfPresent(Int.self, forKey: .timesPerWeek) ?? 3
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
    /// Свои повторы напоминания (Pro). nil - стандартные.
    var repeatCount: Int?
    var repeatInterval: Int?
    /// Часть дня для привычки без напоминания.
    var partOfDay: PartOfDay?
    /// Пауза (Pro): в эти дни привычка не нужна и серия не прерывается.
    var pausedFrom: Date?
    var pausedUntil: Date?
    /// Цель на день для количественной привычки (Pro), например 8 стаканов.
    var target: Int?
    var unit: String?
    /// Минимальная версия, например "хотя бы 5 приседаний". Засчитывается как выполнение.
    var minimumVersion: String?
    /// Привычка, после отметки которой напомнить об этой.
    var chainAfter: UUID?

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
         sortOrder: Int = 0,
         partOfDay: PartOfDay? = nil,
         target: Int? = nil,
         unit: String? = nil) {
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
        self.partOfDay = partOfDay
        self.target = target
        self.unit = unit
    }

    enum CodingKeys: String, CodingKey {
        case id, name, details, icon, colorIndex, groupID, schedule, reminder, createdAt, isArchived, sortOrder
        case repeatCount, repeatInterval, partOfDay, pausedFrom, pausedUntil, target, unit, minimumVersion, chainAfter
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
        repeatCount = try c.decodeIfPresent(Int.self, forKey: .repeatCount)
        repeatInterval = try c.decodeIfPresent(Int.self, forKey: .repeatInterval)
        partOfDay = try? c.decodeIfPresent(PartOfDay.self, forKey: .partOfDay)
        pausedFrom = try c.decodeIfPresent(Date.self, forKey: .pausedFrom)
        pausedUntil = try c.decodeIfPresent(Date.self, forKey: .pausedUntil)
        target = try c.decodeIfPresent(Int.self, forKey: .target)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        minimumVersion = try c.decodeIfPresent(String.self, forKey: .minimumVersion)
        chainAfter = try c.decodeIfPresent(UUID.self, forKey: .chainAfter)
    }

    /// Повторы напоминания с учётом Pro: без Pro всегда стандартные.
    func repeatRule(isPro: Bool) -> RepeatRule {
        if isPro, let count = repeatCount, let interval = repeatInterval {
            return RepeatRule(count: count, interval: interval)
        }
        return .standard
    }

    /// Цель на день: больше 1 только у количественных привычек с Pro.
    func dailyTarget(isPro: Bool) -> Int {
        guard isPro, let target, target > 1 else { return 1 }
        return target
    }

    /// Часть дня: по времени напоминания или выбранная вручную.
    var effectivePartOfDay: PartOfDay {
        if let reminder { return PartOfDay(time: reminder) }
        return partOfDay ?? .anytime
    }
}

struct RepeatRule: Hashable {
    var count: Int
    var interval: Int

    /// Бесплатная версия: 3 повтора каждые 15 минут.
    static let standard = RepeatRule(count: 3, interval: 15)
    static let intervals = [5, 10, 15, 30, 60]
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
    /// Сколько уже сделано у количественной привычки.
    var count: Int?
    /// Выполнена минимальная версия.
    var isMinimum: Bool?
}

struct NoteEntry: Identifiable, Hashable {
    let day: String
    let note: String
    var id: String { day }
}

// MARK: - Настройки

enum HomeLayout: String, Codable, Hashable, CaseIterable {
    /// Секции "Утро", "День", "Вечер", "В любое время".
    case partsOfDay
    /// Один список: с напоминанием по времени, остальные после.
    case byTime
}

struct AppSettings: Codable, Hashable {
    /// Pro включён. Пока покупок нет, это тестовый переключатель в настройках.
    var proUnlocked: Bool = true
    /// Общий выключатель напоминаний приложения.
    var remindersEnabled: Bool = true
    var homeLayout: HomeLayout = .partsOfDay
    var doneToBottom: Bool = false
    var summaryEnabled: Bool = true
    var summaryTime = ReminderTime(hour: 21, minute: 0)
    var onboardingDone = false
    var gestureHintShown = false
    var backgroundID = "default"
    var avatarID = "sprout"
    /// Ачивки, о которых уже показали поздравление.
    var seenAchievements: [String] = []

    init() {}

    enum CodingKeys: String, CodingKey {
        case proUnlocked, remindersEnabled, homeLayout, doneToBottom, summaryEnabled, summaryTime
        case onboardingDone, gestureHintShown, backgroundID, avatarID, seenAchievements
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proUnlocked = try c.decodeIfPresent(Bool.self, forKey: .proUnlocked) ?? true
        remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? true
        homeLayout = (try? c.decodeIfPresent(HomeLayout.self, forKey: .homeLayout)) ?? .partsOfDay
        doneToBottom = try c.decodeIfPresent(Bool.self, forKey: .doneToBottom) ?? false
        summaryEnabled = try c.decodeIfPresent(Bool.self, forKey: .summaryEnabled) ?? true
        summaryTime = try c.decodeIfPresent(ReminderTime.self, forKey: .summaryTime) ?? ReminderTime(hour: 21, minute: 0)
        onboardingDone = try c.decodeIfPresent(Bool.self, forKey: .onboardingDone) ?? false
        gestureHintShown = try c.decodeIfPresent(Bool.self, forKey: .gestureHintShown) ?? false
        backgroundID = try c.decodeIfPresent(String.self, forKey: .backgroundID) ?? "default"
        avatarID = try c.decodeIfPresent(String.self, forKey: .avatarID) ?? "sprout"
        seenAchievements = try c.decodeIfPresent([String].self, forKey: .seenAchievements) ?? []
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
    static let freeHabitLimit = 5

    var isPro: Bool { settings.proUnlocked }

    /// Можно ли добавить ещё одну активную привычку. Архивные не считаются.
    var canAddHabit: Bool { isPro || activeHabits.count < Self.freeHabitLimit }

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

    /// Сколько сделано у количественной привычки (выполненная считается полной).
    func count(of habit: Habit, day: String) -> Int {
        let target = habit.dailyTarget(isPro: isPro)
        if status(habit.id, day: day) == .done { return target }
        return min(checkIn(habit.id, day: day)?.count ?? 0, target)
    }

    mutating func setStatus(_ status: CheckStatus?, habitID: UUID, day: String) {
        let k = Self.key(habitID, day)
        var entry = checkIns[k] ?? CheckIn(status: nil, note: nil, updatedAt: Date())
        entry.status = status
        entry.isMinimum = nil
        if status == nil { entry.count = nil }
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

    /// Нажатие на отметку: обычная привычка переключается,
    /// количественная прибавляет 1, а после цели сбрасывается.
    mutating func tap(habitID: UUID, day: String) {
        guard let habit = habits.first(where: { $0.id == habitID }) else { return }
        let target = habit.dailyTarget(isPro: isPro)
        let k = Self.key(habitID, day)
        var entry = checkIns[k] ?? CheckIn(status: nil, note: nil, updatedAt: Date())
        entry.isMinimum = nil
        if target <= 1 {
            entry.status = entry.status == .done ? nil : .done
            entry.count = nil
        } else if entry.status == .done {
            entry.status = nil
            entry.count = nil
        } else {
            let next = (entry.count ?? 0) + 1
            entry.count = next
            entry.status = next >= target ? .done : nil
        }
        entry.updatedAt = Date()
        store(entry, key: k)
    }

    /// Отмечает выполнение минимальной версии.
    mutating func markMinimum(habitID: UUID, day: String) {
        let k = Self.key(habitID, day)
        var entry = checkIns[k] ?? CheckIn(status: nil, note: nil, updatedAt: Date())
        entry.status = .done
        entry.isMinimum = true
        entry.updatedAt = Date()
        store(entry, key: k)
    }

    /// Уменьшает счётчик количественной привычки на 1.
    mutating func decrement(habitID: UUID, day: String) {
        guard let habit = habits.first(where: { $0.id == habitID }) else { return }
        let current = count(of: habit, day: day)
        guard current > 0 else { return }
        let k = Self.key(habitID, day)
        var entry = checkIns[k] ?? CheckIn(status: nil, note: nil, updatedAt: Date())
        entry.status = nil
        entry.count = current - 1 > 0 ? current - 1 : nil
        entry.updatedAt = Date()
        store(entry, key: k)
    }

    private mutating func store(_ entry: CheckIn, key: String) {
        let hasNote = !(entry.note ?? "").isEmpty
        if entry.status == nil && !hasNote && (entry.count ?? 0) == 0 {
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

    // MARK: N раз в неделю

    /// Сколько раз привычка выполнена за неделю, в которую входит день.
    func weekDoneCount(_ habit: Habit, weekOf date: Date, excluding excluded: Date? = nil, calendar: Calendar = .app) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        var count = 0
        var day = week.start
        while day < week.end {
            if excluded.map({ !calendar.isDate($0, inSameDayAs: day) }) ?? true,
               status(habit.id, day: DayKey.make(day, calendar: calendar)) == .done {
                count += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    /// Недельная цель уже выполнена без учёта этого дня.
    func weeklyGoalMet(_ habit: Habit, before date: Date, calendar: Calendar = .app) -> Bool {
        guard habit.schedule.kind == .weekly else { return false }
        return weekDoneCount(habit, weekOf: date, excluding: date, calendar: calendar) >= habit.schedule.timesPerWeek
    }
}
