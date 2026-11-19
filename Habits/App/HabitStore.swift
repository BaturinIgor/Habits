import Foundation
import Observation
import SwiftUI
import WidgetKit

/// Единый источник данных приложения.
@MainActor
@Observable
final class HabitStore {
    static let shared = HabitStore()

    private(set) var data: AppData

    private init() {
        #if DEBUG
        if TestMode.isUITest {
            // Автотесты: каждый запуск с одних и тех же демо-данных.
            data = UITestSupport.demoData()
            DataFile.save(data)
            return
        }
        #endif
        data = DataFile.load()
    }

    /// Перечитывает файл: данные могли измениться из виджета или уведомления.
    func reloadFromDisk() {
        if let fresh = DataFile.loadIfAvailable() {
            data = fresh
            revision += 1
        }
    }

    /// Растёт при каждом сохранении, чтобы экраны могли реагировать на любые изменения.
    private(set) var revision = 0

    private func commit(syncFamily: Bool = true) {
        revision += 1
        DataFile.save(data)
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) {
            // Кнопки привычек в Пункте управления показывают, отмечена ли привычка.
            ControlCenter.shared.reloadAllControls()
        }
        let snapshot = data
        Task { await NotificationPlanner.reschedule(data: snapshot) }
        // Siri узнаёт новые названия привычек для фраз вроде «Отметь Зарядку».
        HabitsShortcuts.updateAppShortcutParameters()
        if syncFamily {
            FamilySync.shared.scheduleSync()
        }
    }

    func reschedule() async {
        await NotificationPlanner.reschedule(data: data)
    }

    // MARK: Привычки

    func habit(_ id: UUID) -> Habit? {
        data.habits.first { $0.id == id }
    }

    /// source: откуда сохранена привычка (для статистики). Правкой считается только сохранение из редактора.
    func upsert(_ habit: Habit, source: HabitSource) {
        if let index = data.habits.firstIndex(where: { $0.id == habit.id }) {
            data.habits[index] = habit
            if source == .editor { Analytics.shared.action(.edit) }
        } else {
            var new = habit
            new.sortOrder = (data.habits.map(\.sortOrder).max() ?? -1) + 1
            data.habits.append(new)
            Analytics.shared.send(.habitCreated(new, source: source))
        }
        commit()
    }

    func deleteHabit(_ id: UUID) {
        // Заработанное считается из истории отметок, поэтому без этого удаление привычки
        // уменьшало бы баланс искр и опыт питомца. Разницу запоминаем в кошельке.
        let earnedBefore = economy.report.total
        let xpBefore = data.wallet.pet.map { Pets.xp($0, data: data) }
        if let removed = habit(id) {
            let age = Calendar.app.dateComponents([.day], from: removed.createdAt, to: Date()).day ?? 0
            Analytics.shared.send(.habitDeleted(ageDays: max(0, age), isQuit: removed.isQuit))
        }
        data.habits.removeAll { $0.id == id }
        data.removeCheckIns(for: id)
        revision += 1
        let lostSparks = earnedBefore - economy.report.total
        if lostSparks > 0 { data.wallet.keptEarned += lostSparks }
        if let xpBefore, let pet = data.wallet.pet {
            let lostXP = xpBefore - Pets.xp(pet, data: data)
            if lostXP > 0 { data.wallet.keptPetXP += lostXP }
        }
        commit()
        Task { await NotificationPlanner.clearDelivered(habitID: id) }
    }

    /// Срыв у привычки, которую бросают: счёт дней начинается заново, рекорд запоминается.
    func relapse(_ id: UUID) {
        guard let index = data.habits.firstIndex(where: { $0.id == id }), data.habits[index].quit != nil else { return }
        data.habits[index].quit?.relapse()
        Analytics.shared.action(.relapse)
        commit()
    }

    func setArchived(_ id: UUID, _ archived: Bool) {
        guard let index = data.habits.firstIndex(where: { $0.id == id }) else { return }
        data.habits[index].isArchived = archived
        Analytics.shared.action(archived ? .archive : .unarchive)
        commit()
    }

    /// Задаёт новый ручной порядок: переданные привычки встают на свои места в этом порядке,
    /// а все привычки получают уникальные номера, чтобы порядок не "залипал".
    /// Меняет относительный порядок переданных привычек, не трогая остальные:
    /// они занимают те же позиции в общем списке, но в новом порядке.
    func applyManualOrder(_ ids: [UUID]) {
        var global = data.habits.sorted(by: Habit.manualOrder).map(\.id)
        let moved = Set(ids)
        let slots = global.indices.filter { moved.contains(global[$0]) }
        guard slots.count == ids.count else { return }
        for (slot, id) in zip(slots, ids) { global[slot] = id }
        for (position, id) in global.enumerated() {
            if let index = data.habits.firstIndex(where: { $0.id == id }) {
                data.habits[index].sortOrder = position
            }
        }
        Analytics.shared.action(.reorder)
        revision += 1
        DataFile.save(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Искры, магазин, питомец

    struct Economy {
        var report = SparkReport()
        var balance = 0
    }

    @ObservationIgnored private var economyCache: (revision: Int, value: Economy)?
    @ObservationIgnored private var factsCache: (revision: Int, value: AchievementFacts)?

    /// Сводка для ачивок: считается один раз на изменение, её используют и искры, и баннер ачивок.
    var achievementFacts: AchievementFacts {
        _ = revision
        if let cache = factsCache, cache.revision == revision { return cache.value }
        let facts = AchievementFacts(data: data)
        factsCache = (revision, facts)
        return facts
    }

    /// Открытые ачивки. Однажды открытая ачивка остаётся навсегда (она запоминается
    /// в seenAchievements), даже если удалить привычку, на которой она держалась.
    var unlockedAchievementIDs: Set<String> {
        let facts = achievementFacts
        let known = Set(Achievements.all.map(\.id))
        let kept = Set(data.settings.seenAchievements).intersection(known)
        return Set(Achievements.all.filter { $0.isUnlocked(facts) }.map(\.id)).union(kept)
    }

    /// Заработанное и баланс, пересчитываются после изменений.
    var economy: Economy {
        _ = revision
        if let cache = economyCache, cache.revision == revision { return cache.value }
        let facts = achievementFacts
        let unlocked = unlockedAchievementIDs.count
        let report = Sparks.report(data, facts: facts, unlockedAchievements: unlocked)
        let value = Economy(report: report, balance: Sparks.balance(earned: report.total, data: data))
        economyCache = (revision, value)
        return value
    }

    /// Запоминает заработанное, чтобы виджет мог кормить питомца без полного подсчёта.
    func syncEarnedSnapshot() {
        let total = economy.report.total
        guard data.wallet.earnedSnapshot != total else { return }
        data.wallet.earnedSnapshot = total
        DataFile.save(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Списывает искры, если хватает. Возвращает true при успехе.
    private func spend(_ amount: Int) -> Bool {
        guard economy.balance >= amount else { return false }
        data.wallet.spent += amount
        return true
    }

    @discardableResult
    func buyReward(_ reward: Reward) -> Bool {
        guard case .shop(let price) = reward.unlock, !data.wallet.purchases.contains(reward.id), spend(price) else { return false }
        data.wallet.purchases.append(reward.id)
        if reward.kind == .avatar { data.settings.avatarID = reward.id } else { data.settings.backgroundID = reward.id }
        Analytics.shared.action(.rewardBuy)
        commit()
        return true
    }

    var extraFreezesThisMonth: Int { data.wallet.extraFreezes[Wallet.monthKey(Date()), default: 0] }

    @discardableResult
    func buyFreeze() -> Bool {
        guard extraFreezesThisMonth < Sparks.maxExtraFreezes, spend(Sparks.freezePrice) else { return false }
        data.wallet.extraFreezes[Wallet.monthKey(Date()), default: 0] += 1
        Analytics.shared.action(.freezeBuy)
        commit()
        return true
    }

    // MARK: Починка серии

    /// Серию, прервавшуюся из-за последнего пропуска (вчера или позавчера), можно вернуть за искры.
    /// Возвращает пропущенный день и длину серии после починки, или nil, если чинить нечего.
    func streakRepair(for habit: Habit) -> (day: String, streak: Int)? {
        guard !habit.isQuit, !habit.isArchived, habit.schedule.kind != .weekly, habit.schedule.kind != .once else { return nil }
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: Date())
        var missed: Date?
        for back in 1...2 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            if habit.isScheduled(on: day) { missed = day; break }
        }
        guard let missed else { return nil }
        let key = DayKey.make(missed)
        let repairKey = AppData.key(habit.id, key)
        guard data.status(habit.id, day: key) == nil, !data.wallet.repairs.contains(repairKey) else { return nil }
        let current = Stats.habit(habit, in: data)
        guard !current.frozenDays.contains(key) else { return nil }
        var test = data
        test.wallet.repairs.append(repairKey)
        let fixed = Stats.habit(habit, in: test).currentStreak
        guard fixed > current.currentStreak, fixed >= 3 else { return nil }
        return (key, fixed)
    }

    @discardableResult
    func repairStreak(_ habitID: UUID) -> Bool {
        guard let habit = self.habit(habitID), let repair = streakRepair(for: habit), spend(Sparks.repairPrice) else { return false }
        data.wallet.repairs.append(AppData.key(habitID, repair.day))
        // Старые починки больше не влияют на текущие серии, но нужны для лучшей серии.
        if data.wallet.repairs.count > 500 { data.wallet.repairs.removeFirst(data.wallet.repairs.count - 500) }
        Analytics.shared.action(.streakRepair)
        commit()
        return true
    }

    /// Подарок Pro раз в месяц. Возвращает число подаренных искр.
    @discardableResult
    func claimProGift() -> Int {
        let month = Wallet.monthKey(Date())
        guard data.isPro, !data.wallet.proMonths.contains(month) else { return 0 }
        data.wallet.proMonths.append(month)
        commit()
        return Sparks.proMonthlyGift
    }

    func adoptPet(species: String, name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        data.wallet.pet = PetState(species: species, name: clean.isEmpty ? String(localized: "Buddy") : clean, adoptedAt: Date())
        data.wallet.keptPetXP = 0
        Analytics.shared.send(.petAdopted(species: species))
        commit()
    }

    func renamePet(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        data.wallet.pet?.name = clean
        Analytics.shared.action(.petRename)
        commit()
    }

    var feedsToday: Int { data.wallet.pet?.feeds[DayKey.make(Date()), default: 0] ?? 0 }

    @discardableResult
    func feedPet() -> Bool {
        guard data.wallet.pet != nil, feedsToday < Sparks.feedsPerDay, spend(Sparks.feedPrice) else { return false }
        // Меняем копию и записываем целиком: чтение и запись data в одном
        // выражении приводили к падению (одновременный доступ к памяти).
        guard var pet = data.wallet.pet else { return false }
        pet.feeds[DayKey.make(Date()), default: 0] += 1
        // Старые записи о кормлении не нужны дольше года.
        if let cutoff = Calendar.app.date(byAdding: .day, value: -400, to: Date()) {
            let old = DayKey.make(cutoff)
            pet.feeds = pet.feeds.filter { $0.key >= old }
        }
        data.wallet.pet = pet
        Analytics.shared.action(.petFeed)
        commit()
        return true
    }

    /// Запоминает, когда питомец впервые дошёл до каждой стадии: от этого
    /// дня начинаются подарки и бонусные заморозки. Возвращает новую стадию, если она появилась.
    @discardableResult
    func syncPetStage() -> PetStage? {
        guard var pet = data.wallet.pet else { return nil }
        let current = PetStage.stage(xp: Pets.xp(pet, data: data))
        let now = Date()
        var reached: PetStage?
        var newStages = 0
        for stage in PetStage.allCases where stage > .egg && stage <= current && pet.stageReached[String(stage.rawValue)] == nil {
            pet.stageReached[String(stage.rawValue)] = now
            reached = stage
            newStages += 1
        }
        guard let reached else { return nil }
        // Несколько стадий сразу - это догоняющее заполнение (обновление, импорт, восстановление),
        // а не настоящий переход: в статистику не шлём, чтобы не портить воронку.
        if newStages == 1 { Analytics.shared.send(.petStageReached(stage: reached.rawValue)) }
        data.wallet.pet = pet
        commit()
        return reached
    }

    /// Сменить вид питомца; платный вид сначала покупается.
    @discardableResult
    func setPetSpecies(_ species: PetSpecies) -> Bool {
        if !Pets.isOwned(species, data: data) {
            guard !species.needsPro, let price = species.price, spend(price) else { return false }
            data.wallet.ownedPets.append(species.id)
        }
        data.wallet.pet?.species = species.id
        Analytics.shared.action(.petSpecies)
        commit()
        return true
    }

    // MARK: Группы

    @discardableResult
    func addGroup(name: String) -> HabitGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = HabitGroup(
            name: trimmed.isEmpty ? String(localized: "New group") : trimmed,
            sortOrder: (data.groups.map(\.sortOrder).max() ?? -1) + 1
        )
        data.groups.append(group)
        Analytics.shared.action(.groupAdd)
        commit()
        return group
    }

    func renameGroup(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = data.groups.firstIndex(where: { $0.id == id }) else { return }
        data.groups[index].name = trimmed
        Analytics.shared.action(.groupRename)
        commit()
    }

    func deleteGroup(_ id: UUID) {
        Analytics.shared.action(.groupDelete)
        data.groups.removeAll { $0.id == id }
        for index in data.habits.indices where data.habits[index].groupID == id {
            data.habits[index].groupID = nil
        }
        commit()
    }

    // MARK: Семейные группы

    /// Изменения, пришедшие из iCloud. Обратно в iCloud их не отправляем.
    func applyFamilyChanges(_ change: (inout AppData) -> Void) {
        change(&data)
        commit(syncFamily: false)
    }

    func setFamily(_ family: FamilyShare?, for groupID: UUID) {
        guard let index = data.groups.firstIndex(where: { $0.id == groupID }) else { return }
        if data.groups[index].family == nil, family?.isOwner == true { Analytics.shared.send(.familyGroupCreated) }
        data.groups[index].family = family
        commit(syncFamily: false)
    }

    /// Группа, в которую пригласили. id совпадает с id группы у владельца.
    func addFamilyGroup(id: UUID, name: String, family: FamilyShare) {
        if !data.groups.contains(where: { $0.id == id && $0.family != nil }) { Analytics.shared.send(.familyGroupJoined) }
        if let index = data.groups.firstIndex(where: { $0.id == id }) {
            data.groups[index].family = family
        } else {
            data.groups.append(HabitGroup(
                id: id,
                name: name,
                sortOrder: (data.groups.map(\.sortOrder).max() ?? -1) + 1,
                family: family
            ))
        }
        commit(syncFamily: false)
    }

    /// Выход из чужой группы: её привычки уходят вместе с ней.
    func removeGroupWithHabits(_ id: UUID) {
        let ids = data.habits.filter { $0.groupID == id }.map(\.id)
        data.habits.removeAll { $0.groupID == id }
        for habitID in ids { data.removeCheckIns(for: habitID) }
        data.groups.removeAll { $0.id == id }
        commit(syncFamily: false)
    }

    func moveGroups(from source: IndexSet, to destination: Int) {
        var groups = data.sortedGroups
        groups.move(fromOffsets: source, toOffset: destination)
        Analytics.shared.action(.groupReorder)
        for (position, group) in groups.enumerated() {
            if let index = data.groups.firstIndex(where: { $0.id == group.id }) {
                data.groups[index].sortOrder = position
            }
        }
        commit()
    }

    // MARK: Отметки

    func status(_ id: UUID, on day: Date) -> CheckStatus? {
        data.status(id, day: DayKey.make(day))
    }

    func toggleDone(_ id: UUID, on day: Date) {
        let key = DayKey.make(day)
        let wasDone = data.status(id, day: key) == .done
        data.tap(habitID: id, day: key)
        trackCheck(data.status(id, day: key) == .done && !wasDone ? .check : .uncheck, day: key)
        commit()
        Task { await NotificationPlanner.clearDelivered(habitID: id, day: key) }
        notifyChain(after: id, day: day)
    }

    func markMinimum(_ id: UUID, on day: Date) {
        let key = DayKey.make(day)
        data.markMinimum(habitID: id, day: key)
        trackCheck(.minimum, day: key)
        commit()
        Task { await NotificationPlanner.clearDelivered(habitID: id, day: key) }
        notifyChain(after: id, day: day)
    }

    private func trackCheck(_ action: AnalyticsAction, day: String) {
        Analytics.shared.action(action)
        if day != DayKey.make(Date()) { Analytics.shared.action(.checkPastDay) }
    }

    /// Связка привычек: после отметки напоминаем о следующих.
    private func notifyChain(after id: UUID, day: Date) {
        NotificationPlanner.notifyChain(after: id, day: day, data: data)
    }

    func setStatus(_ status: CheckStatus?, for id: UUID, on day: Date) {
        let key = DayKey.make(day)
        data.setStatus(status, habitID: id, day: key)
        trackCheck(status == .done ? .check : status == nil ? .clearStatus : .skip, day: key)
        commit()
        if status != nil {
            Task { await NotificationPlanner.clearDelivered(habitID: id, day: key) }
        }
        if status == .done { notifyChain(after: id, day: day) }
    }

    func setNote(_ note: String, for id: UUID, dayKey: String) {
        data.setNote(note, habitID: id, day: dayKey)
        Analytics.shared.action(.noteSave)
        // Заметки влияют на ачивки (и искры за них), поэтому экраны должны пересчитаться.
        revision += 1
        DataFile.save(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Настроение

    func mood(on dayKey: String) -> MoodEntry? {
        data.moods[dayKey]
    }

    /// Оценка настроения за день. Заметка остаётся прежней, если её не передали.
    func setMood(_ level: Int, note: String? = nil, dayKey: String) {
        var entry = data.moods[dayKey] ?? MoodEntry(level: level)
        entry.level = min(5, max(1, level))
        if let note {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.note = trimmed.isEmpty ? nil : trimmed
        }
        entry.updatedAt = Date()
        data.moods[dayKey] = entry
        Analytics.shared.action(.moodSet)
        // Без перепланирования уведомлений и семейной синхронизации: дневник личный.
        revision += 1
        DataFile.save(data)
    }

    func removeMood(dayKey: String) {
        data.moods[dayKey] = nil
        Analytics.shared.action(.moodRemove)
        revision += 1
        DataFile.save(data)
    }

    // MARK: Слова

    /// Ответ на карточку слова. Сохраняем без перепланирования уведомлений: это частое действие.
    func answerWord(language: String, wordID: String, known: Bool) {
        data.answerWord(language: language, wordID: wordID, known: known, day: DayKey.make(Date()))
        Analytics.shared.action(known ? .wordKnown : .wordUnknown)
        revision += 1
        DataFile.save(data)
    }

    /// Слова дня пройдены: отмечаем привычку выполненной.
    func completeWords(_ habitID: UUID) {
        guard status(habitID, on: Date()) != .done else { return }
        setStatus(.done, for: habitID, on: Date())
    }

    // MARK: Настройки

    func setPro(_ enabled: Bool) {
        if data.settings.proUnlocked != enabled { Analytics.shared.send(.proChanged(active: enabled)) }
        data.settings.proUnlocked = enabled
        if !enabled {
            // Pro-награды без Pro не носим, возвращаем стандартные.
            if Rewards.background(data.settings.backgroundID).needsPro { data.settings.backgroundID = Rewards.backgrounds[0].id }
            if Rewards.avatar(data.settings.avatarID).needsPro { data.settings.avatarID = Rewards.avatars[0].id }
            // Блокировка по Face ID доступна только в Pro.
            data.settings.appLock = false
        }
        commit()
    }

    func decrement(_ id: UUID, on day: Date) {
        data.decrement(habitID: id, day: DayKey.make(day))
        Analytics.shared.action(.decrement)
        commit()
    }

    /// Изменение настроек с сохранением и пересчётом уведомлений.
    func updateSettings(_ change: (inout AppSettings) -> Void) {
        let before = data.settings
        change(&data.settings)
        // Считаем только то, что меняет пользователь, а не служебные отметки.
        var after = data.settings
        after.seenAchievements = before.seenAchievements
        after.whatsNewSeen = before.whatsNewSeen
        after.onboardingDone = before.onboardingDone
        after.gestureHintShown = before.gestureHintShown
        if after != before { Analytics.shared.action(.settingsChange) }
        commit()
    }

    // MARK: Резервная копия

    func exportData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(data)) ?? Data()
    }

    /// Заменяет все данные содержимым файла. Возвращает false, если файл не подошёл.
    func importData(from url: URL) -> Bool {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let raw = try? Data(contentsOf: url) else { return false }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let imported = try? decoder.decode(AppData.self, from: raw) else { return false }
        Analytics.shared.action(.importData)
        replaceAll(with: imported)
        return true
    }

    /// Заменяет все данные (импорт файла или копия из iCloud).
    func replaceAll(with imported: AppData) {
        data = imported
        commit()
    }

    /// Возвращает false, если вернуть из архива нельзя из-за лимита бесплатной версии.
    @discardableResult
    func unarchive(_ id: UUID) -> Bool {
        guard data.canAddHabit else { return false }
        setArchived(id, false)
        return true
    }

    // MARK: Ответ на уведомление

    func handleNotificationAction(_ action: String, habitID: UUID?, day: String?) async {
        guard let habitID, let day else { return }
        guard action == NotificationPlanner.doneAction || action == NotificationPlanner.skipAction else { return }
        guard let fresh = DataFile.loadIfAvailable() else { return }
        data = fresh
        guard data.habits.contains(where: { $0.id == habitID }) else { return }
        data.setStatus(action == NotificationPlanner.doneAction ? .done : .skipped, habitID: habitID, day: day)
        Analytics.shared.action(action == NotificationPlanner.doneAction ? .checkFromNotification : .skipFromNotification)
        revision += 1
        DataFile.save(data)
        WidgetCenter.shared.reloadAllTimelines()
        await NotificationPlanner.clearDelivered(habitID: habitID, day: day)
        await NotificationPlanner.reschedule(data: data)
        if action == NotificationPlanner.doneAction, let date = DayKey.date(day) {
            notifyChain(after: habitID, day: date)
        }
        // Отметка из уведомления сразу уходит родным: приложение в фоне, и само
        // оно синхронизировалось бы только при следующем открытии.
        await FamilySync.shared.syncAll(reload: false)
    }
}
