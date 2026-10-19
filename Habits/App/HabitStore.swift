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

    private func commit() {
        revision += 1
        DataFile.save(data)
        WidgetCenter.shared.reloadAllTimelines()
        let snapshot = data
        Task { await NotificationPlanner.reschedule(data: snapshot) }
    }

    func reschedule() async {
        await NotificationPlanner.reschedule(data: data)
    }

    // MARK: Привычки

    func habit(_ id: UUID) -> Habit? {
        data.habits.first { $0.id == id }
    }

    func upsert(_ habit: Habit) {
        if let index = data.habits.firstIndex(where: { $0.id == habit.id }) {
            data.habits[index] = habit
        } else {
            var new = habit
            new.sortOrder = (data.habits.map(\.sortOrder).max() ?? -1) + 1
            data.habits.append(new)
        }
        commit()
    }

    func deleteHabit(_ id: UUID) {
        data.habits.removeAll { $0.id == id }
        data.removeCheckIns(for: id)
        commit()
        Task { await NotificationPlanner.clearDelivered(habitID: id) }
    }

    func setArchived(_ id: UUID, _ archived: Bool) {
        guard let index = data.habits.firstIndex(where: { $0.id == id }) else { return }
        data.habits[index].isArchived = archived
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

    /// Заработанное и баланс, пересчитываются после изменений.
    var economy: Economy {
        _ = revision
        if let cache = economyCache, cache.revision == revision { return cache.value }
        let facts = AchievementFacts(data: data)
        let unlocked = Achievements.all.filter { $0.isUnlocked(facts) }.count
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
        commit()
        return true
    }

    var extraFreezesThisMonth: Int { data.wallet.extraFreezes[Wallet.monthKey(Date()), default: 0] }

    @discardableResult
    func buyFreeze() -> Bool {
        guard extraFreezesThisMonth < Sparks.maxExtraFreezes, spend(Sparks.freezePrice) else { return false }
        data.wallet.extraFreezes[Wallet.monthKey(Date()), default: 0] += 1
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
        commit()
    }

    func renamePet(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        data.wallet.pet?.name = clean
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
        commit()
        return true
    }

    /// Сменить вид питомца; платный вид сначала покупается.
    @discardableResult
    func setPetSpecies(_ species: PetSpecies) -> Bool {
        if !Pets.isOwned(species, data: data) {
            guard !species.needsPro, let price = species.price, spend(price) else { return false }
            data.wallet.ownedPets.append(species.id)
        }
        data.wallet.pet?.species = species.id
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
        commit()
        return group
    }

    func renameGroup(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = data.groups.firstIndex(where: { $0.id == id }) else { return }
        data.groups[index].name = trimmed
        commit()
    }

    func deleteGroup(_ id: UUID) {
        data.groups.removeAll { $0.id == id }
        for index in data.habits.indices where data.habits[index].groupID == id {
            data.habits[index].groupID = nil
        }
        commit()
    }

    func moveGroups(from source: IndexSet, to destination: Int) {
        var groups = data.sortedGroups
        groups.move(fromOffsets: source, toOffset: destination)
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
        data.tap(habitID: id, day: key)
        commit()
        Task { await NotificationPlanner.clearDelivered(habitID: id, day: key) }
        notifyChain(after: id, day: day)
    }

    func markMinimum(_ id: UUID, on day: Date) {
        let key = DayKey.make(day)
        data.markMinimum(habitID: id, day: key)
        commit()
        Task { await NotificationPlanner.clearDelivered(habitID: id, day: key) }
        notifyChain(after: id, day: day)
    }

    /// Связка привычек: после отметки напоминаем о следующих.
    private func notifyChain(after id: UUID, day: Date) {
        NotificationPlanner.notifyChain(after: id, day: day, data: data)
    }

    func setStatus(_ status: CheckStatus?, for id: UUID, on day: Date) {
        let key = DayKey.make(day)
        data.setStatus(status, habitID: id, day: key)
        commit()
        if status != nil {
            Task { await NotificationPlanner.clearDelivered(habitID: id, day: key) }
        }
        if status == .done { notifyChain(after: id, day: day) }
    }

    func setNote(_ note: String, for id: UUID, dayKey: String) {
        data.setNote(note, habitID: id, day: dayKey)
        DataFile.save(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Настройки

    func setPro(_ enabled: Bool) {
        data.settings.proUnlocked = enabled
        if !enabled {
            // Pro-награды без Pro не носим, возвращаем стандартные.
            if Rewards.background(data.settings.backgroundID).needsPro { data.settings.backgroundID = Rewards.backgrounds[0].id }
            if Rewards.avatar(data.settings.avatarID).needsPro { data.settings.avatarID = Rewards.avatars[0].id }
        }
        commit()
    }

    func decrement(_ id: UUID, on day: Date) {
        data.decrement(habitID: id, day: DayKey.make(day))
        commit()
    }

    /// Изменение настроек с сохранением и пересчётом уведомлений.
    func updateSettings(_ change: (inout AppSettings) -> Void) {
        change(&data.settings)
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
        data = imported
        commit()
        return true
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
        revision += 1
        DataFile.save(data)
        WidgetCenter.shared.reloadAllTimelines()
        await NotificationPlanner.clearDelivered(habitID: habitID, day: day)
        await NotificationPlanner.reschedule(data: data)
        if action == NotificationPlanner.doneAction, let date = DayKey.date(day) {
            notifyChain(after: habitID, day: date)
        }
    }
}
