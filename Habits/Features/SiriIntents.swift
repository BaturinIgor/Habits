import AppIntents
import CoreSpotlight
import Foundation

// Голосовые команды для Siri и приложения «Команды».
// Фразы для Siri переводятся в Localization/*.lproj/AppShortcuts.strings (tools/l10n/generate.py).

/// Готовая переведённая строка как ответ Siri.
private func say(_ text: String) -> IntentDialog {
    IntentDialog("\(text)")
}

// MARK: - Привычка как параметр

struct HabitEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static let defaultQuery = HabitEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(_ habit: Habit) {
        id = habit.id
        name = habit.name
    }
}

struct HabitEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [HabitEntity] {
        await MainActor.run {
            HabitStore.shared.reloadFromDisk()
            return HabitStore.shared.data.trackedHabits
                .filter { identifiers.contains($0.id) }
                .map(HabitEntity.init)
        }
    }

    func entities(matching string: String) async throws -> [HabitEntity] {
        await MainActor.run {
            HabitStore.shared.reloadFromDisk()
            return Self.matching(string, in: HabitStore.shared.data)
        }
    }

    func suggestedEntities() async throws -> [HabitEntity] {
        await MainActor.run {
            HabitStore.shared.reloadFromDisk()
            return Self.suggested(in: HabitStore.shared.data)
        }
    }

    /// Поиск по названию без учёта регистра и диакритики: «зарядка» найдёт «Зарядка утром».
    static func matching(_ string: String, in data: AppData) -> [HabitEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return suggested(in: data) }
        return data.trackedHabits
            .filter { $0.name.localizedStandardContains(query) }
            .map(HabitEntity.init)
    }

    /// Сначала то, что запланировано на сегодня.
    static func suggested(in data: AppData, now: Date = Date()) -> [HabitEntity] {
        let today = data.habits(on: now)
        let rest = data.trackedHabits.filter { habit in !today.contains { $0.id == habit.id } }
        return (today + rest).map(HabitEntity.init)
    }
}

// MARK: - Привычки в Spotlight

/// На iOS 18 привычки попадают в Spotlight как IndexedEntity (их же видят Команды),
/// на iOS 17 обычными записями CoreSpotlight.
@available(iOS 18.0, *)
extension HabitEntity: IndexedEntity {}

@MainActor
enum HabitSpotlight {
    static let domain = "habits"
    /// Что уже отдали в индекс: переиндексируем, только когда меняются названия или состав привычек.
    private static var lastSignature: [String]?

    static func signature(_ data: AppData) -> [String] {
        data.trackedHabits.map { "\($0.id.uuidString)|\($0.name)" }
    }

    static func update(_ data: AppData) {
        let signature = signature(data)
        guard signature != lastSignature, CSSearchableIndex.isIndexingAvailable() else { return }
        lastSignature = signature
        let entities = data.trackedHabits.map(HabitEntity.init)
        Task {
            let index = CSSearchableIndex.default()
            if #available(iOS 18.0, *) {
                try? await index.deleteAppEntities(ofType: HabitEntity.self)
                try? await index.indexAppEntities(entities)
            } else {
                try? await index.deleteSearchableItems(withDomainIdentifiers: [domain])
                let items = entities.map { entity in
                    let attributes = CSSearchableItemAttributeSet(contentType: .text)
                    attributes.title = entity.name
                    attributes.displayName = entity.name
                    return CSSearchableItem(uniqueIdentifier: entity.id.uuidString, domainIdentifier: domain, attributeSet: attributes)
                }
                try? await index.indexSearchableItems(items)
            }
        }
    }
}

// MARK: - Отметить привычку

struct MarkHabitDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Check off a habit"
    static let description = IntentDescription("Marks a habit as done for today.")

    @Parameter(title: "Habit", requestValueDialog: "Which habit?")
    var habit: HabitEntity

    init() {}

    init(habit: HabitEntity) {
        self.habit = habit
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = HabitStore.shared
        store.reloadFromDisk()
        let answer = Self.run(habit, store: store)
        // Искры за отметку: виджет кормит питомца по этому снимку, не дожидаясь открытия приложения.
        store.syncEarnedSnapshot()
        return .result(dialog: say(answer))
    }

    /// Отметка без Siri: её же вызывают тесты с хранилищем в памяти. Возвращает ответ Siri.
    @MainActor
    static func run(_ habit: HabitEntity, store: HabitStore, now: Date = Date()) -> String {
        let habitName = habit.name
        guard store.habit(habit.id) != nil else {
            return String(localized: "Habit not found.")
        }
        if store.status(habit.id, on: now) == .done {
            return String(localized: "\(habitName) is already done today.")
        }
        // setStatus сохраняет файл и обновляет виджеты, Пункт управления и часы (HabitStore.commit).
        store.setStatus(.done, for: habit.id, on: now)
        return String(localized: "Done: \(habitName)")
    }
}

// MARK: - Записать настроение

/// Оценка настроения для Siri: те же пять ступеней, что в дневнике (MoodLevel).
enum MoodLevelOption: Int, AppEnum {
    case awful = 1, bad, okay, good, great

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mood"
    static let caseDisplayRepresentations: [MoodLevelOption: DisplayRepresentation] = [
        .awful: "Awful",
        .bad: "Bad",
        .okay: "Okay",
        .good: "Good",
        .great: "Great",
    ]

    var level: MoodLevel { MoodLevel(clamping: rawValue) }
}

struct LogMoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log mood"
    static let description = IntentDescription("Saves how you feel today in the mood journal.")

    @Parameter(title: "Mood", requestValueDialog: "How are you feeling?")
    var mood: MoodLevelOption

    init() {}

    init(mood: MoodLevelOption) {
        self.mood = mood
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = HabitStore.shared
        store.reloadFromDisk()
        return .result(dialog: say(Self.run(mood, store: store)))
    }

    /// Оценка за сегодня, как карточка настроения на экране «Сегодня»: без Pro, заметка остаётся.
    /// Pro нужен только для истории старше недели, а записывать можно всем.
    @MainActor
    static func run(_ mood: MoodLevelOption, store: HabitStore, now: Date = Date()) -> String {
        store.setMood(mood.rawValue, dayKey: DayKey.make(now))
        let text = "\(mood.level.emoji) \(mood.level.title)"
        return String(localized: "Mood saved: \(text)")
    }
}

// MARK: - Таймер привычки

struct StartHabitTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start a habit timer"
    static let description = IntentDescription("Starts a countdown with a Live Activity. When time's up, the habit is checked off.")

    @Parameter(title: "Habit", requestValueDialog: "Which habit?")
    var habit: HabitEntity

    @Parameter(title: "Minutes", inclusiveRange: (1, 240))
    var minutes: Int?

    init() {}

    init(habit: HabitEntity, minutes: Int? = nil) {
        self.habit = habit
        self.minutes = minutes
    }

    /// Что сделать с просьбой: отдельно от запуска, чтобы проверять без ActivityKit.
    enum Plan: Equatable {
        case needsPro
        case notFound
        case alreadyDone
        case start(minutes: Int)
    }

    /// Правила как на экране «Сегодня»: таймер только в Pro и только для неотмеченной привычки.
    /// Длительность: из запроса, иначе из настроек привычки, иначе 10 минут (как в HabitTimerView).
    static func plan(for id: UUID, minutes: Int?, data: AppData, now: Date = Date()) -> Plan {
        guard data.isPro else { return .needsPro }
        guard let habit = data.trackedHabits.first(where: { $0.id == id }) else { return .notFound }
        if data.status(id, day: DayKey.make(now)) == .done { return .alreadyDone }
        return .start(minutes: max(1, minutes ?? habit.timerMinutes ?? 10))
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = HabitStore.shared
        store.reloadFromDisk()
        let habitName = habit.name
        switch Self.plan(for: habit.id, minutes: minutes, data: store.data) {
        case .needsPro:
            return .result(dialog: say(String(localized: "The habit timer is part of Pro. Open ZenHab to get Pro.")))
        case .notFound:
            return .result(dialog: say(String(localized: "Habit not found.")))
        case .alreadyDone:
            return .result(dialog: say(String(localized: "\(habitName) is already done today.")))
        case .start(let minutes):
            guard let model = store.habit(habit.id) else {
                return .result(dialog: say(String(localized: "Habit not found.")))
            }
            // Live Activity можно запустить из фона: интент помечен LiveActivityIntent.
            await HabitTimer.shared.start(model, minutes: minutes)
            return .result(dialog: say(String(localized: "Timer started: \(habitName), \(minutes) min.")))
        }
    }
}

// MARK: - Добавить привычку

struct AddHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a habit"
    static let description = IntentDescription("Creates a habit or a reminder from a phrase, for example “Dog pills once a month on the 15th at 9 am”.")

    @Parameter(title: "What to add", requestValueDialog: "What should I add?")
    var phrase: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = HabitStore.shared
        store.reloadFromDisk()
        guard store.data.canAddHabit else {
            return .result(dialog: say(String(localized: "The free version has reached its habit limit. Open ZenHab to get Pro.")))
        }
        let voice = VoiceHabitParser.parse(phrase)
        var habit = Habit(
            icon: .symbol(SymbolCatalog.symbols.randomElement() ?? "star.fill"),
            colorIndex: Int.random(in: 0..<Palette.colors.count),
            schedule: voice.schedule,
            reminder: voice.reminder
        )
        habit.name = voice.name
        habit.partOfDay = .anytime
        store.upsert(habit, source: .siri)
        let summary = habit.scheduleSummary
        let habitName = habit.name
        if let reminder = habit.reminder {
            let time = reminder.text
            return .result(dialog: say(String(localized: "Added \(habitName): \(summary), at \(time).")))
        }
        return .result(dialog: say(String(localized: "Added \(habitName): \(summary).")))
    }
}

// MARK: - Что осталось на сегодня

struct TodayLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "What's left today"
    static let description = IntentDescription("Lists the habits that aren't checked off today.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = HabitStore.shared
        store.reloadFromDisk()
        let data = store.data
        let key = DayKey.make(Date())
        let left = data.habits(on: Date()).filter { data.status($0.id, day: key) == nil }
        if left.isEmpty {
            return .result(dialog: say(String(localized: "Everything is done for today.")))
        }
        let names = ListFormatter.localizedString(byJoining: left.map(\.name))
        return .result(dialog: say(String(localized: "Left for today: \(names).")))
    }
}

// MARK: - Фразы для Siri

struct HabitsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkHabitDoneIntent(),
            phrases: [
                "Check off \(\.$habit) in \(.applicationName)",
                "Mark \(\.$habit) in \(.applicationName)",
                "Check off a habit in \(.applicationName)",
            ],
            shortTitle: "Check off a habit",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: AddHabitIntent(),
            phrases: [
                "Add a habit in \(.applicationName)",
                "Add a reminder in \(.applicationName)",
                "New habit in \(.applicationName)",
            ],
            shortTitle: "Add a habit",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: TodayLeftIntent(),
            phrases: [
                "What's left in \(.applicationName)",
                "What's left today in \(.applicationName)",
            ],
            shortTitle: "What's left today",
            systemImageName: "list.bullet"
        )
        AppShortcut(
            intent: LogMoodIntent(),
            phrases: [
                "Log my mood in \(.applicationName)",
                "Mood check-in in \(.applicationName)",
            ],
            shortTitle: "Log mood",
            systemImageName: "face.smiling"
        )
        AppShortcut(
            intent: StartHabitTimerIntent(),
            phrases: [
                "Start a timer for \(\.$habit) in \(.applicationName)",
                "Start a habit timer in \(.applicationName)",
            ],
            shortTitle: "Start a habit timer",
            systemImageName: "timer"
        )
    }
}
