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

    /// Перестановка внутри списка привычек (например, одной группы).
    func reorder(_ ids: [UUID], from source: IndexSet, to destination: Int) {
        var newOrder = ids
        newOrder.move(fromOffsets: source, toOffset: destination)
        let orders = ids.compactMap { id in data.habits.first { $0.id == id }?.sortOrder }.sorted()
        guard orders.count == newOrder.count else { return }
        for (position, id) in newOrder.enumerated() {
            if let index = data.habits.firstIndex(where: { $0.id == id }) {
                data.habits[index].sortOrder = orders[position]
            }
        }
        commit()
    }

    // MARK: Группы

    @discardableResult
    func addGroup(name: String) -> HabitGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = HabitGroup(
            name: trimmed.isEmpty ? "Новая группа" : trimmed,
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
        data.toggleDone(habitID: id, day: key)
        commit()
        Task { await NotificationPlanner.clearDelivered(habitID: id, day: key) }
    }

    func setStatus(_ status: CheckStatus?, for id: UUID, on day: Date) {
        let key = DayKey.make(day)
        data.setStatus(status, habitID: id, day: key)
        commit()
        if status != nil {
            Task { await NotificationPlanner.clearDelivered(habitID: id, day: key) }
        }
    }

    func setNote(_ note: String, for id: UUID, dayKey: String) {
        data.setNote(note, habitID: id, day: dayKey)
        DataFile.save(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Настройки

    func setRepeatCount(_ count: Int) {
        data.settings.repeatCount = max(0, count)
        commit()
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
    }
}
