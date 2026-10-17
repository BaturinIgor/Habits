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
        }
    }

    private func commit() {
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
    }

    func setArchived(_ id: UUID, _ archived: Bool) {
        guard let index = data.habits.firstIndex(where: { $0.id == id }) else { return }
        data.habits[index].isArchived = archived
        commit()
    }

    /// Задаёт новый ручной порядок: переданные привычки встают на свои места в этом порядке,
    /// а все привычки получают уникальные номера, чтобы порядок не "залипал".
    func applyManualOrder(_ ids: [UUID]) {
        var global = data.habits.sorted { $0.sortOrder < $1.sortOrder }.map(\.id)
        let moved = Set(ids)
        let slots = global.indices.filter { moved.contains(global[$0]) }
        guard slots.count == ids.count else { return }
        for (slot, id) in zip(slots, ids) { global[slot] = id }
        for (position, id) in global.enumerated() {
            if let index = data.habits.firstIndex(where: { $0.id == id }) {
                data.habits[index].sortOrder = position
            }
        }
        DataFile.save(data)
        WidgetCenter.shared.reloadAllTimelines()
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
        let key = DayKey.make(day)
        guard data.status(id, day: key) == .done, Calendar.app.isDateInToday(day),
              data.settings.remindersEnabled else { return }
        let next = data.habits(on: day).filter { $0.chainAfter == id && data.status($0.id, day: key) == nil }
        for habit in next {
            NotificationPlanner.notifyChained(habit, day: key)
        }
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
        data.setStatus(action == NotificationPlanner.doneAction ? .done : .skipped, habitID: habitID, day: day)
        DataFile.save(data)
        WidgetCenter.shared.reloadAllTimelines()
        await NotificationPlanner.clearDelivered(habitID: habitID, day: day)
        await NotificationPlanner.reschedule(data: data)
        if action == NotificationPlanner.doneAction, let date = DayKey.date(day) {
            notifyChain(after: habitID, day: date)
        }
    }
}
