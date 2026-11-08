import AppIntents
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
            return HabitStore.shared.data.activeHabits
                .filter { identifiers.contains($0.id) }
                .map(HabitEntity.init)
        }
    }

    func entities(matching string: String) async throws -> [HabitEntity] {
        await MainActor.run {
            HabitStore.shared.reloadFromDisk()
            return HabitStore.shared.data.activeHabits
                .filter { $0.name.localizedStandardContains(string) }
                .map(HabitEntity.init)
        }
    }

    func suggestedEntities() async throws -> [HabitEntity] {
        await MainActor.run {
            HabitStore.shared.reloadFromDisk()
            let data = HabitStore.shared.data
            // Сначала то, что запланировано на сегодня.
            let today = data.habits(on: Date())
            let rest = data.activeHabits.filter { habit in !today.contains { $0.id == habit.id } }
            return (today + rest).map(HabitEntity.init)
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
        let habitName = habit.name
        guard store.habit(habit.id) != nil else {
            return .result(dialog: say(String(localized: "Habit not found.")))
        }
        if store.status(habit.id, on: Date()) == .done {
            return .result(dialog: say(String(localized: "\(habitName) is already done today.")))
        }
        store.setStatus(.done, for: habit.id, on: Date())
        return .result(dialog: say(String(localized: "Done: \(habitName)")))
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
        store.upsert(habit)
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
    }
}
