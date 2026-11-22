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
        /// Каждые N дней от даты начала ("через день" = 2).
        case everyNDays
        /// Раз в месяц, в то же число, что и дата начала.
        case monthly
        /// Раз в год, в тот же день и месяц, что и дата начала.
        case yearly
    }

    var kind: Kind
    /// Дни недели по Calendar: 1 = воскресенье ... 7 = суббота.
    var weekdays: Set<Int>
    var startDate: Date
    var endDate: Date?
    var onceDate: Date
    /// Для вида "N раз в неделю".
    var timesPerWeek: Int
    /// Для вида "каждые N дней".
    var intervalDays: Int

    init(kind: Kind = .repeating,
         weekdays: Set<Int> = Set(1...7),
         startDate: Date = Calendar.app.startOfDay(for: Date()),
         endDate: Date? = nil,
         onceDate: Date = Calendar.app.startOfDay(for: Date()),
         timesPerWeek: Int = 3,
         intervalDays: Int = 2) {
        self.kind = kind
        self.weekdays = weekdays
        self.startDate = startDate
        self.endDate = endDate
        self.onceDate = onceDate
        self.timesPerWeek = timesPerWeek
        self.intervalDays = intervalDays
    }

    enum CodingKeys: String, CodingKey {
        case kind, weekdays, startDate, endDate, onceDate, timesPerWeek, intervalDays
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
        intervalDays = max(2, try c.decodeIfPresent(Int.self, forKey: .intervalDays) ?? 2)
    }

    /// Дни недели пишем по порядку. Порядок элементов Set случайный, и без сортировки одна и та же
    /// привычка каждый раз давала другой JSON: семейная синхронизация считала её изменённой
    /// и бесконечно отправляла туда-обратно между телефонами.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(weekdays.sorted(), forKey: .weekdays)
        try c.encode(startDate, forKey: .startDate)
        try c.encodeIfPresent(endDate, forKey: .endDate)
        try c.encode(onceDate, forKey: .onceDate)
        try c.encode(timesPerWeek, forKey: .timesPerWeek)
        try c.encode(intervalDays, forKey: .intervalDays)
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
    /// Изучение слов: код языка из словаря (например "es") и сколько новых слов в день.
    var wordsLanguage: String?
    var wordsPerDay: Int?
    /// Уровень слов: 0 начальный, 1 средний, 2 продвинутый.
    var wordsLevel: Int?
    /// Вредная привычка, которую человек бросает: вместо отметок счётчик дней без неё.
    var quit: QuitInfo?
    /// Автоотметка по данным Apple Health (Pro): например, 10 000 шагов.
    var health: HealthLink?
    /// Таймер (Pro): привычка на время, например «Медитация 10 мин».
    var timerMinutes: Int?
    /// Умное время (KAN-135): напоминание само сдвигается к обычному времени отметки. nil - выключено.
    var smartTime: Bool?

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
         unit: String? = nil,
         wordsLanguage: String? = nil,
         wordsPerDay: Int? = nil,
         wordsLevel: Int? = nil) {
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
        self.wordsLanguage = wordsLanguage
        self.wordsPerDay = wordsPerDay
        self.wordsLevel = wordsLevel
    }

    enum CodingKeys: String, CodingKey {
        case id, name, details, icon, colorIndex, groupID, schedule, reminder, createdAt, isArchived, sortOrder
        case repeatCount, repeatInterval, partOfDay, pausedFrom, pausedUntil, target, unit, minimumVersion, chainAfter
        case wordsLanguage, wordsPerDay, wordsLevel, quit, health, timerMinutes, smartTime
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
        wordsLanguage = try c.decodeIfPresent(String.self, forKey: .wordsLanguage)
        wordsPerDay = try c.decodeIfPresent(Int.self, forKey: .wordsPerDay)
        wordsLevel = try c.decodeIfPresent(Int.self, forKey: .wordsLevel)
        quit = try? c.decodeIfPresent(QuitInfo.self, forKey: .quit)
        health = try? c.decodeIfPresent(HealthLink.self, forKey: .health)
        timerMinutes = try c.decodeIfPresent(Int.self, forKey: .timerMinutes)
        smartTime = try? c.decodeIfPresent(Bool.self, forKey: .smartTime)
    }

    /// Бросаю: счётчик дней без привычки вместо ежедневных отметок.
    var isQuit: Bool { quit != nil }

    /// Привычка "учить слова": отметка ставится сама, когда пройдены слова дня.
    var isWords: Bool { wordsLanguage != nil }

    /// Повторы напоминания с учётом Pro: без Pro всегда стандартные.
    /// Ручной порядок: sortOrder, при равенстве дата создания и id, чтобы порядок не прыгал.
    static func manualOrder(_ a: Habit, _ b: Habit) -> Bool {
        if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }

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

// MARK: - Apple Health

/// Связь привычки с показателем Apple Health: когда показатель за день дошёл до цели,
/// привычка отмечается сама.
struct HealthLink: Codable, Hashable {
    enum Metric: String, Codable, CaseIterable, Identifiable {
        case steps
        case exerciseMinutes
        case mindfulMinutes
        case sleepHours
        case water
        case workouts

        var id: String { rawValue }

        var title: String {
            switch self {
            case .steps: String(localized: "Steps")
            case .exerciseMinutes: String(localized: "Exercise minutes")
            case .mindfulMinutes: String(localized: "Mindful minutes")
            case .sleepHours: String(localized: "Hours of sleep")
            case .water: String(localized: "Water, liters")
            case .workouts: String(localized: "Workouts")
            }
        }

        var symbol: String {
            switch self {
            case .steps: "figure.walk"
            case .exerciseMinutes: "flame.fill"
            case .mindfulMinutes: "brain.head.profile"
            case .sleepHours: "bed.double.fill"
            case .water: "drop.fill"
            case .workouts: "dumbbell.fill"
            }
        }

        var defaultGoal: Double {
            switch self {
            case .steps: 10_000
            case .exerciseMinutes: 30
            case .mindfulMinutes: 10
            case .sleepHours: 7
            case .water: 2
            case .workouts: 1
            }
        }

        /// Шаг изменения цели в редакторе.
        var step: Double {
            switch self {
            case .steps: 500
            case .exerciseMinutes, .mindfulMinutes: 5
            case .sleepHours, .water: 0.5
            case .workouts: 1
            }
        }

        var range: ClosedRange<Double> {
            switch self {
            case .steps: 500...50_000
            case .exerciseMinutes: 5...300
            case .mindfulMinutes: 1...120
            case .sleepHours: 4...12
            case .water: 0.5...5
            case .workouts: 1...5
            }
        }

        func format(_ value: Double) -> String {
            switch self {
            case .sleepHours, .water:
                value.formatted(.number.precision(.fractionLength(0...1)))
            default:
                Int(value.rounded(.down)).formatted()
            }
        }
    }

    var metric: Metric
    var goal: Double
}

// MARK: - Бросаю вредную привычку

struct QuitInfo: Codable, Hashable {
    /// Когда начал бросать.
    var startedAt: Date
    /// Начало текущего периода без привычки: старт или последний срыв.
    var since: Date
    /// Сколько уходило на привычку в день (Pro), в валюте телефона.
    var dailyCost: Double?
    /// Все срывы, от старых к новым.
    var relapses: [Date] = []
    /// Лучший период без привычки до последнего срыва, в днях.
    var bestDays: Int = 0

    init(startedAt: Date = Date(), dailyCost: Double? = nil) {
        self.startedAt = startedAt
        self.since = startedAt
        self.dailyCost = dailyCost
    }

    enum CodingKeys: String, CodingKey {
        case startedAt, since, dailyCost, relapses, bestDays
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        since = try c.decodeIfPresent(Date.self, forKey: .since) ?? startedAt
        dailyCost = try c.decodeIfPresent(Double.self, forKey: .dailyCost)
        relapses = try c.decodeIfPresent([Date].self, forKey: .relapses) ?? []
        bestDays = try c.decodeIfPresent(Int.self, forKey: .bestDays) ?? 0
    }

    /// Полных дней без привычки в текущем периоде.
    func days(now: Date = Date(), calendar: Calendar = .app) -> Int {
        max(0, calendar.dateComponents([.day], from: since, to: now).day ?? 0)
    }

    /// Рекорд с учётом текущего периода.
    func best(now: Date = Date()) -> Int { max(bestDays, days(now: now)) }

    /// Всего дней без привычки с начала: каждый срыв отнимает один день.
    func totalDays(now: Date = Date(), calendar: Calendar = .app) -> Int {
        let all = max(0, calendar.dateComponents([.day], from: startedAt, to: now).day ?? 0)
        return max(0, all - relapses.count)
    }

    /// Сколько сэкономлено с начала.
    func saved(now: Date = Date()) -> Double? {
        guard let dailyCost, dailyCost > 0 else { return nil }
        return dailyCost * Double(totalDays(now: now))
    }

    /// Сорвался: запоминаем рекорд и начинаем новый период.
    mutating func relapse(at date: Date = Date()) {
        bestDays = best(now: date)
        relapses.append(date)
        since = date
    }

    /// Вехи: 1 день, 3 дня, неделя, 2 недели, месяц, 3 месяца, полгода, год.
    static let milestones = [1, 3, 7, 14, 30, 90, 180, 365]

    /// Следующая веха и доля пути к ней (после года - каждый следующий год).
    func nextMilestone(now: Date = Date()) -> (days: Int, progress: Double) {
        let current = days(now: now)
        let previous = Self.milestones.last { $0 <= current } ?? 0
        let next = Self.milestones.first { $0 > current } ?? ((current / 365) + 1) * 365
        let start = current >= 365 ? (current / 365) * 365 : previous
        let span = max(1, next - start)
        return (next, Double(current - start) / Double(span))
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
    /// Группа общая с семьёй через iCloud.
    var family: FamilyShare? = nil
}

/// Где в iCloud лежит общая группа.
struct FamilyShare: Codable, Hashable {
    var zoneName: String
    var ownerName: String
    /// Группу создал этот человек (у остальных она в общей базе).
    var isOwner: Bool
    /// Ссылка-приглашение.
    var url: URL?
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
    /// Смещение часового пояса (секунды от GMT) в момент отметки: умное время считает время отметки
    /// по местным часам того дня, даже если потом человек переехал в другой пояс. У старых отметок нет.
    var tz: Int?
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
    /// Секции по группам привычек, внутри по времени.
    case byGroup
}

struct AppSettings: Codable, Hashable {
    /// Pro включён. Пока покупок нет, это тестовый переключатель в настройках.
    #if SIDELOAD
    static let proDefault = true
    #else
    static let proDefault = false
    #endif
    var proUnlocked: Bool = AppSettings.proDefault
    /// Общий выключатель напоминаний приложения.
    var remindersEnabled: Bool = true
    var homeLayout: HomeLayout = .partsOfDay
    var doneToBottom: Bool = false
    var summaryEnabled: Bool = true
    /// Число неотмеченных привычек на иконке приложения.
    var badgeEnabled: Bool = true
    var summaryTime = ReminderTime(hour: 21, minute: 0)
    var onboardingDone = false
    var gestureHintShown = false
    var backgroundID = "default"
    var avatarID = "sprout"
    /// Ачивки, о которых уже показали поздравление.
    var seenAchievements: [String] = []
    /// Версия, для которой уже показали экран «Что нового».
    var whatsNewSeen: String = ""
    /// Блокировка приложения по Face ID (Pro).
    var appLock: Bool = false
    /// Карточка настроения на экране «Сегодня».
    var moodCard: Bool = true
    /// Пейволл в конце онбординга уже показан (1.7, KAN-122): второй раз не показываем.
    var onboardingPaywallSeen: Bool = false
    /// Подсказки первого дня на «Сегодня» после онбординга (1.7, KAN-169): подсказка отметить первую привычку,
    /// потом поздравление. Выключается, когда поздравление закрыли.
    var firstDayGuide: Bool = false

    init() {}

    enum CodingKeys: String, CodingKey {
        case proUnlocked, remindersEnabled, homeLayout, doneToBottom, summaryEnabled, summaryTime
        case onboardingDone, gestureHintShown, backgroundID, avatarID, seenAchievements, badgeEnabled, whatsNewSeen
        case appLock, moodCard
        case onboardingPaywallSeen, firstDayGuide
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proUnlocked = try c.decodeIfPresent(Bool.self, forKey: .proUnlocked) ?? AppSettings.proDefault
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
        badgeEnabled = try c.decodeIfPresent(Bool.self, forKey: .badgeEnabled) ?? true
        whatsNewSeen = try c.decodeIfPresent(String.self, forKey: .whatsNewSeen) ?? ""
        appLock = try c.decodeIfPresent(Bool.self, forKey: .appLock) ?? false
        moodCard = try c.decodeIfPresent(Bool.self, forKey: .moodCard) ?? true
        onboardingPaywallSeen = try c.decodeIfPresent(Bool.self, forKey: .onboardingPaywallSeen) ?? false
        firstDayGuide = try c.decodeIfPresent(Bool.self, forKey: .firstDayGuide) ?? false
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
    var wallet: Wallet = Wallet()
    /// Прогресс изучения слов. Ключ: "<язык>|<номер слова>".
    var words: [String: WordCard] = [:]
    /// Дневник настроения. Ключ: yyyy-MM-dd.
    var moods: [String: MoodEntry] = [:]

    init() {}

    enum CodingKeys: String, CodingKey {
        case version, habits, groups, checkIns, settings, wallet, words, moods
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        habits = try c.decodeIfPresent([Habit].self, forKey: .habits) ?? []
        groups = try c.decodeIfPresent([HabitGroup].self, forKey: .groups) ?? []
        checkIns = try c.decodeIfPresent([String: CheckIn].self, forKey: .checkIns) ?? [:]
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        wallet = (try? c.decodeIfPresent(Wallet.self, forKey: .wallet)) ?? Wallet()
        words = (try? c.decodeIfPresent([String: WordCard].self, forKey: .words)) ?? [:]
        moods = (try? c.decodeIfPresent([String: MoodEntry].self, forKey: .moods)) ?? [:]
    }
}

// MARK: - Настроение

/// Запись дневника настроения за день: оценка от 1 (плохо) до 5 (отлично) и заметка.
struct MoodEntry: Codable, Hashable {
    var level: Int
    var note: String?
    var updatedAt: Date

    init(level: Int, note: String? = nil, updatedAt: Date = Date()) {
        self.level = min(5, max(1, level))
        self.note = note
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey { case level, note, updatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = min(5, max(1, try c.decodeIfPresent(Int.self, forKey: .level) ?? 3))
        note = try c.decodeIfPresent(String.self, forKey: .note)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

// MARK: - Карточка слова

/// Интервальное повторение: чем выше коробка, тем реже слово возвращается.
struct WordCard: Codable, Hashable {
    var box: Int
    /// День следующего повтора, yyyy-MM-dd.
    var due: String
    /// День, когда слово показали впервые.
    var introduced: String
    /// День последнего ответа.
    var lastSeen: String
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
        // Повторная отметка тем же статусом ничего не меняет: иначе старая отметка
        // получила бы новое время и перестала бы считаться честной (пропала бы искра).
        if status != nil && entry.status == status && entry.isMinimum != true { return }
        entry.status = status
        entry.isMinimum = nil
        if status == nil { entry.count = nil }
        entry.updatedAt = Date()
        entry.tz = TimeZone.current.secondsFromGMT()
        store(entry, key: k)
    }

    mutating func setNote(_ note: String, habitID: UUID, day: String) {
        let k = Self.key(habitID, day)
        var entry = checkIns[k] ?? CheckIn(status: nil, note: nil, updatedAt: Date())
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = trimmed.isEmpty ? nil : trimmed
        // updatedAt не трогаем: по нему считается время отметки для ачивок.
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
        entry.tz = TimeZone.current.secondsFromGMT()
        store(entry, key: k)
    }

    /// Отмечает выполнение минимальной версии.
    mutating func markMinimum(habitID: UUID, day: String) {
        let k = Self.key(habitID, day)
        var entry = checkIns[k] ?? CheckIn(status: nil, note: nil, updatedAt: Date())
        entry.status = .done
        entry.isMinimum = true
        entry.updatedAt = Date()
        entry.tz = TimeZone.current.secondsFromGMT()
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
        habits.filter { !$0.isArchived }.sorted(by: Habit.manualOrder)
    }

    /// Активные привычки с отметками (без тех, что бросают): для статистики.
    var trackedHabits: [Habit] {
        activeHabits.filter { !$0.isQuit }
    }

    var archivedHabits: [Habit] {
        habits.filter { $0.isArchived }.sorted(by: Habit.manualOrder)
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
