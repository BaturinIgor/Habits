import XCTest
@testable import Habits

/// 1.7, KAN-136: логика интентов Siri и Команд без самой Siri (хранилище в памяти).
@MainActor
final class SiriIntentsTests: XCTestCase {
    private func habit(_ name: String, timer: Int? = nil, archived: Bool = false) -> Habit {
        var habit = Habit(name: name, reminder: nil, createdAt: Calendar.app.date(byAdding: .day, value: -10, to: Date())!, isArchived: archived)
        habit.timerMinutes = timer
        return habit
    }

    // MARK: Поиск привычки

    func testQueryFindsHabitByNameIgnoringCase() {
        var data = AppData()
        let workout = habit("Зарядка утром")
        data.habits = [habit("Чтение"), workout, habit("Вода")]
        let found = HabitEntityQuery.matching("  зарядка ", in: data)
        XCTAssertEqual(found.map(\.id), [workout.id])
        XCTAssertEqual(found.first?.name, "Зарядка утром")
    }

    func testQuerySkipsArchivedAndEmptyQuerySuggestsAll() {
        var data = AppData()
        data.habits = [habit("Read"), habit("Read old", archived: true)]
        XCTAssertEqual(HabitEntityQuery.matching("read", in: data).map(\.name), ["Read"])
        XCTAssertEqual(HabitEntityQuery.matching("", in: data).map(\.name), ["Read"])
        XCTAssertTrue(HabitEntityQuery.matching("swim", in: data).isEmpty)
    }

    func testSpotlightSignatureFollowsNames() {
        var data = AppData()
        let read = habit("Read")
        data.habits = [read]
        let before = HabitSpotlight.signature(data)
        data.habits[0].name = "Read a book"
        XCTAssertNotEqual(HabitSpotlight.signature(data), before)
        XCTAssertEqual(HabitSpotlight.signature(data), ["\(read.id.uuidString)|Read a book"])
    }

    // MARK: Отметить привычку

    func testMarkHabitDoneSetsStatusOnce() {
        var data = AppData()
        let read = habit("Read")
        data.habits = [read]
        let store = HabitStore(inMemory: data)
        let entity = HabitEntity(read)

        XCTAssertEqual(MarkHabitDoneIntent.run(entity, store: store), String(localized: "Done: \("Read")"))
        XCTAssertEqual(store.status(read.id, on: Date()), .done)
        // Повторная отметка ничего не меняет и говорит, что уже готово.
        let habitName = "Read"
        XCTAssertEqual(MarkHabitDoneIntent.run(entity, store: store), String(localized: "\(habitName) is already done today."))
        XCTAssertEqual(store.status(read.id, on: Date()), .done)
    }

    func testMarkUnknownHabit() {
        let store = HabitStore(inMemory: AppData())
        let entity = HabitEntity(habit("Ghost"))
        XCTAssertEqual(MarkHabitDoneIntent.run(entity, store: store), String(localized: "Habit not found."))
    }

    /// Отметка из Siri не заставляет питомца подпрыгивать (это только для касания в приложении),
    /// но засчитывается в искры, как любая другая отметка.
    func testMarkFromSiriCountsForSparks() {
        var data = AppData()
        let read = habit("Read")
        data.habits = [read]
        let store = HabitStore(inMemory: data)
        let before = store.economy.report.total
        _ = MarkHabitDoneIntent.run(HabitEntity(read), store: store)
        XCTAssertEqual(store.petCheers, 0)
        XCTAssertGreaterThan(store.economy.report.total, before)
    }

    // MARK: Настроение

    func testLogMoodSavesTodayAndKeepsNote() {
        var data = AppData()
        let key = DayKey.make(Date())
        data.moods[key] = MoodEntry(level: 2, note: "Плохо спал")
        let store = HabitStore(inMemory: data)
        _ = LogMoodIntent.run(.great, store: store)
        XCTAssertEqual(store.mood(on: key)?.level, 5)
        XCTAssertEqual(store.mood(on: key)?.note, "Плохо спал")
    }

    /// Дневник настроения без Pro: записывать можно и в бесплатной версии, как в карточке на «Сегодня».
    func testLogMoodWorksWithoutPro() {
        let store = HabitStore(inMemory: AppData())
        XCTAssertFalse(store.data.isPro)
        _ = LogMoodIntent.run(.bad, store: store)
        XCTAssertEqual(store.mood(on: DayKey.make(Date()))?.level, 2)
    }

    func testMoodOptionsMatchMoodLevels() {
        XCTAssertEqual(MoodLevelOption.allCases.map(\.level), MoodLevel.allCases)
    }

    // MARK: Таймер

    func testTimerNeedsPro() {
        var data = AppData()
        let meditate = habit("Meditate", timer: 15)
        data.habits = [meditate]
        XCTAssertEqual(StartHabitTimerIntent.plan(for: meditate.id, minutes: nil, data: data), .needsPro)
    }

    func testTimerMinutes() {
        var data = AppData()
        data.settings.proUnlocked = true
        let meditate = habit("Meditate", timer: 15)
        let read = habit("Read")
        data.habits = [meditate, read]
        XCTAssertEqual(StartHabitTimerIntent.plan(for: meditate.id, minutes: nil, data: data), .start(minutes: 15))
        XCTAssertEqual(StartHabitTimerIntent.plan(for: meditate.id, minutes: 5, data: data), .start(minutes: 5))
        // Без своей длительности: 10 минут, как на экране таймера.
        XCTAssertEqual(StartHabitTimerIntent.plan(for: read.id, minutes: nil, data: data), .start(minutes: 10))
        XCTAssertEqual(StartHabitTimerIntent.plan(for: UUID(), minutes: nil, data: data), .notFound)
    }

    func testTimerForDoneHabit() {
        var data = AppData()
        data.settings.proUnlocked = true
        let meditate = habit("Meditate", timer: 15)
        data.habits = [meditate]
        data.setStatus(.done, habitID: meditate.id, day: DayKey.make(Date()))
        XCTAssertEqual(StartHabitTimerIntent.plan(for: meditate.id, minutes: nil, data: data), .alreadyDone)
    }
}
