import CloudKit
import Foundation
import UIKit

/// Общие семейные группы через iCloud (CloudKit sharing).
///
/// Каждая общая группа - отдельная зона в iCloud владельца. В зоне корневая запись группы,
/// записи привычек и отметок; все они дочерние к корню, поэтому одно приглашение (CKShare)
/// открывает доступ ко всей группе. У приглашённых зона видна в общей базе (sharedCloudDatabase).
///
/// Каждая запись хранит JSON того же типа, что и в локальном файле. При синхронизации
/// сравниваем локальный JSON с тем, что было при прошлой синхронизации: так понятно,
/// что изменилось на телефоне и что надо отправить.
///
/// Типы записей нужно один раз создать в CloudKit Console (поле json, тип Bytes)
/// и выкатить в Production: FamilyGroup, FamilyHabit, FamilyCheckIn.
@MainActor
final class FamilySync {
    static let shared = FamilySync()

    /// Семейные группы есть только в сборке для App Store: только ей Apple выдаёт iCloud.
    static var isAvailable: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "FamilySharingEnabled") as? Bool) == true
    }

    /// Последняя ошибка для экрана группы.
    private(set) var lastError: String?

    private lazy var container: CKContainer = {
        let id = Bundle.main.object(forInfoDictionaryKey: "CloudKitContainer") as? String ?? ""
        return CKContainer(identifier: id)
    }()

    private var isSyncing = false
    private var needsAnotherPass = false
    private var pending: Task<Void, Never>?
    private var states: [String: ZoneState]

    private init() {
        states = Self.loadStates()
    }

    // MARK: Типы записей

    private enum RecordType {
        static let group = "FamilyGroup"
        static let habit = "FamilyHabit"
        static let checkIn = "FamilyCheckIn"
    }

    private struct GroupPayload: Codable {
        var name: String
    }

    private struct LocalRecord {
        let type: String
        let json: Data
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    // MARK: Запуск синхронизации

    /// Синхронизация через пару секунд после изменений, чтобы несколько касаний ушли одним запросом.
    func scheduleSync() {
        guard Self.isAvailable, hasFamilyGroups else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await syncAll()
        }
    }

    private var hasFamilyGroups: Bool {
        HabitStore.shared.data.groups.contains { $0.family != nil }
    }

    func syncAll() async {
        guard Self.isAvailable, hasFamilyGroups else { return }
        if isSyncing {
            needsAnotherPass = true
            return
        }
        isSyncing = true
        repeat {
            needsAnotherPass = false
            let store = HabitStore.shared
            store.reloadFromDisk()
            for group in store.data.groups where group.family != nil {
                await sync(groupID: group.id)
            }
        } while needsAnotherPass
        isSyncing = false
        await registerSubscriptionsIfNeeded()
        await HabitStore.shared.reschedule()
    }

    // MARK: Синхронизация одной группы

    private func sync(groupID: UUID) async {
        let store = HabitStore.shared
        guard let group = store.data.group(groupID), let family = group.family else { return }
        let zoneID = CKRecordZone.ID(zoneName: family.zoneName, ownerName: family.ownerName)
        let database = family.isOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
        let key = Self.stateKey(zoneID)
        var state = states[key] ?? ZoneState()

        do {
            // 1. Что изменилось в iCloud.
            var fetched: Fetched
            do {
                fetched = try await fetchChanges(database: database, zoneID: zoneID, token: state.token.flatMap(Self.unarchiveToken))
            } catch let error as CKError where error.code == .changeTokenExpired {
                state.synced = [:]
                fetched = try await fetchChanges(database: database, zoneID: zoneID, token: nil)
            }
            let changed = fetched.changed
            let deleted = fetched.deleted
            let token = fetched.token

            // 2. Применяем чужие изменения. Если запись поменяли или удалили и здесь, побеждает телефон.
            // Локальные правки считаем только сейчас, после загрузки: пока шёл запрос,
            // человек мог удалить привычку, и старая копия из iCloud не должна её вернуть.
            let lastSynced = state.synced
            var fromCloud = Set<String>()
            store.applyFamilyChanges { data in
                let current = Self.localRecords(groupID: groupID, data: data)
                let editedHere = Set(current.filter { lastSynced[$0.key] != $0.value.json }.keys)
                let deletedHere = Set(lastSynced.keys).subtracting(current.keys)
                for record in changed {
                    let name = record.recordID.recordName
                    guard let json = record["json"] as? Data,
                          !editedHere.contains(name), !deletedHere.contains(name) else { continue }
                    Self.apply(name: name, type: record.recordType, json: json, groupID: groupID, to: &data)
                    fromCloud.insert(name)
                }
                for name in deleted where !editedHere.contains(name) {
                    Self.remove(name: name, groupID: groupID, from: &data)
                    fromCloud.insert(name)
                }
            }

            // 3. Отправляем свои изменения (всё, что отличается от прошлой синхронизации и пришло не из iCloud).
            let after = Self.localRecords(groupID: groupID, data: store.data)
            let toSave = Set(after.filter { lastSynced[$0.key] != $0.value.json }.keys).subtracting(fromCloud)
            let locallyDeleted = Set(lastSynced.keys).subtracting(after.keys).subtracting(fromCloud)
            let rootName = groupID.uuidString
            let toDelete = locallyDeleted.filter { $0 != rootName }
            var failed = Set<String>()
            if !toSave.isEmpty || !toDelete.isEmpty {
                failed = try await push(
                    save: toSave.compactMap { name in after[name].map { (name, $0) } },
                    delete: Array(toDelete),
                    zoneID: zoneID,
                    rootName: rootName,
                    database: database
                )
            }

            // 4. Запоминаем, с чем синхронизировались.
            var synced: [String: Data] = [:]
            for (name, record) in after where !failed.contains(name) {
                synced[name] = record.json
            }
            // Неудачные сохранения и удаления оставляем в старом виде, чтобы повторить в следующий раз.
            for name in failed {
                if let old = lastSynced[name] { synced[name] = old } else { synced[name] = nil }
            }
            state.synced = synced
            state.token = token.flatMap(Self.archiveToken)
            states[key] = state
            saveStates()
            lastError = nil
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // Владелец перестал делиться или удалил группу. Привычки остаются у человека как обычные.
            store.setFamily(nil, for: groupID)
            states[key] = nil
            saveStates()
        } catch {
            lastError = Self.describe(error)
        }
    }

    private struct Fetched {
        var changed: [CKRecord] = []
        var deleted: [String] = []
        var token: CKServerChangeToken?
    }

    private func fetchChanges(database: CKDatabase, zoneID: CKRecordZone.ID, token: CKServerChangeToken?) async throws -> Fetched {
        var fetched = Fetched(token: token)
        var moreComing = true
        while moreComing {
            let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: fetched.token)
            for (_, modification) in result.modificationResultsByID {
                if case .success(let value) = modification {
                    fetched.changed.append(value.record)
                }
            }
            fetched.deleted += result.deletions.map(\.recordID.recordName)
            fetched.token = result.changeToken
            moreComing = result.moreComing
        }
        return fetched
    }

    /// Сохраняет и удаляет записи. Возвращает имена, которые не удалось сохранить или удалить.
    private func push(
        save items: [(String, LocalRecord)],
        delete names: [String],
        zoneID: CKRecordZone.ID,
        rootName: String,
        database: CKDatabase
    ) async throws -> Set<String> {
        let rootID = CKRecord.ID(recordName: rootName, zoneID: zoneID)
        var failed = Set<String>()
        // Берём существующие записи с сервера, чтобы не потерять системные поля (в том числе связь с приглашением).
        for chunk in items.chunked(into: 200) {
            let ids = chunk.map { CKRecord.ID(recordName: $0.0, zoneID: zoneID) }
            let existing = (try? await database.records(for: ids)) ?? [:]
            var records: [CKRecord] = []
            for (name, item) in chunk {
                let id = CKRecord.ID(recordName: name, zoneID: zoneID)
                let record: CKRecord
                if case .success(let found)? = existing[id] {
                    record = found
                } else {
                    record = CKRecord(recordType: item.type, recordID: id)
                }
                record["json"] = item.json as CKRecordValue
                if name != rootName {
                    record.setParent(rootID)
                }
                records.append(record)
            }
            let (saveResults, _) = try await database.modifyRecords(
                saving: records, deleting: [], savePolicy: .changedKeys, atomically: false
            )
            for (id, result) in saveResults {
                if case .failure = result { failed.insert(id.recordName) }
            }
        }
        for chunk in names.chunked(into: 200) {
            let ids = chunk.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
            let (_, deleteResults) = try await database.modifyRecords(saving: [], deleting: ids, savePolicy: .changedKeys, atomically: false)
            for (id, result) in deleteResults {
                // Уже удалённая запись — это успех.
                if case .failure(let error) = result, (error as? CKError)?.code != .unknownItem {
                    failed.insert(id.recordName)
                }
            }
        }
        return failed
    }

    // MARK: Приглашение

    /// Делает группу общей и возвращает ссылку-приглашение.
    func share(groupID: UUID) async throws -> URL {
        let store = HabitStore.shared
        guard let group = store.data.group(groupID) else { throw FamilyError.groupNotFound }
        if let url = group.family?.url, group.family?.isOwner == true { return url }
        guard try await container.accountStatus() == .available else { throw FamilyError.noAccount }

        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneName: "family-\(groupID.uuidString)")
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])

        let rootName = groupID.uuidString
        let root = CKRecord(recordType: RecordType.group, recordID: CKRecord.ID(recordName: rootName, zoneID: zone.zoneID))
        let payload = try Self.encoder.encode(GroupPayload(name: group.name))
        root["json"] = payload as CKRecordValue
        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = group.name as CKRecordValue
        // Вступить может любой, у кого есть ссылка: её отправляют родным в мессенджере.
        share.publicPermission = .readWrite

        let (results, _) = try await database.modifyRecords(saving: [root, share], deleting: [], savePolicy: .allKeys)
        guard let saved = try results[share.recordID]?.get() as? CKShare, let url = saved.url else {
            throw FamilyError.noLink
        }

        // Корень уже в iCloud, остальное отправит обычная синхронизация.
        let key = Self.stateKey(zone.zoneID)
        states[key] = ZoneState(token: nil, synced: [rootName: payload])
        saveStates()
        store.setFamily(FamilyShare(zoneName: zone.zoneID.zoneName, ownerName: zone.zoneID.ownerName, isOwner: true, url: url), for: groupID)
        await syncAll()
        return url
    }

    /// Человек открыл ссылку-приглашение.
    func accept(_ metadata: CKShare.Metadata) async {
        guard Self.isAvailable, let rootID = metadata.hierarchicalRootRecordID,
              let groupID = UUID(uuidString: rootID.recordName) else { return }
        let store = HabitStore.shared
        // Владелец открыл свою же ссылку.
        if store.data.group(groupID)?.family?.isOwner == true { return }
        do {
            _ = try await container.accept(metadata)
            let title = metadata.share[CKShare.SystemFieldKey.title] as? String ?? String(localized: "Family")
            let zoneID = rootID.zoneID
            states[Self.stateKey(zoneID)] = ZoneState()
            saveStates()
            store.addFamilyGroup(
                id: groupID,
                name: title,
                family: FamilyShare(zoneName: zoneID.zoneName, ownerName: zoneID.ownerName, isOwner: false, url: metadata.share.url)
            )
            await syncAll()
        } catch {
            lastError = Self.describe(error)
        }
    }

    /// Владелец перестаёт делиться (зона удаляется у всех), приглашённый выходит из группы.
    func endSharing(groupID: UUID) async throws {
        let store = HabitStore.shared
        guard let family = store.data.group(groupID)?.family else { return }
        let zoneID = CKRecordZone.ID(zoneName: family.zoneName, ownerName: family.ownerName)
        let database = family.isOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
        do {
            _ = try await database.modifyRecordZones(saving: [], deleting: [zoneID])
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // Уже удалена.
        }
        states[Self.stateKey(zoneID)] = nil
        saveStates()
        if family.isOwner {
            store.setFamily(nil, for: groupID)
        } else {
            store.removeGroupWithHabits(groupID)
        }
    }

    // MARK: Push от iCloud

    private var subscriptionsKey: String { "familySubscriptionsSaved" }

    private func registerSubscriptionsIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: subscriptionsKey) else { return }
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        var ok = true
        for (database, id) in [(container.privateCloudDatabase, "family-private"), (container.sharedCloudDatabase, "family-shared")] {
            let subscription = CKDatabaseSubscription(subscriptionID: id)
            subscription.notificationInfo = info
            do {
                _ = try await database.save(subscription)
            } catch {
                ok = false
            }
        }
        if ok { UserDefaults.standard.set(true, forKey: subscriptionsKey) }
    }

    // MARK: Локальные записи

    private static func habitName(_ id: UUID) -> String { "habit-" + id.uuidString }
    private static func checkInName(_ key: String) -> String { "check-" + key.replacingOccurrences(of: "|", with: "-") }

    private static func localRecords(groupID: UUID, data: AppData) -> [String: LocalRecord] {
        var result: [String: LocalRecord] = [:]
        guard let group = data.group(groupID) else { return result }
        if let json = try? encoder.encode(GroupPayload(name: group.name)) {
            result[groupID.uuidString] = LocalRecord(type: RecordType.group, json: json)
        }
        let habits = data.habits.filter { $0.groupID == groupID }
        let ids = Set(habits.map(\.id.uuidString))
        for habit in habits {
            if let json = try? encoder.encode(habit) {
                result[habitName(habit.id)] = LocalRecord(type: RecordType.habit, json: json)
            }
        }
        for (key, checkIn) in data.checkIns {
            guard let separator = key.firstIndex(of: "|"), ids.contains(String(key[..<separator])),
                  let json = try? encoder.encode(checkIn) else { continue }
            result[checkInName(key)] = LocalRecord(type: RecordType.checkIn, json: json)
        }
        return result
    }

    /// "check-<UUID>-<yyyy-MM-dd>" -> "<UUID>|<yyyy-MM-dd>"
    private static func checkInKey(fromName name: String) -> String? {
        let body = name.dropFirst("check-".count)
        guard body.count > 37 else { return nil }
        let id = body.prefix(36)
        let day = body.dropFirst(37)
        guard UUID(uuidString: String(id)) != nil else { return nil }
        return "\(id)|\(day)"
    }

    private static func apply(name: String, type: String, json: Data, groupID: UUID, to data: inout AppData) {
        let decoder = JSONDecoder()
        switch type {
        case RecordType.group:
            guard let payload = try? decoder.decode(GroupPayload.self, from: json),
                  let index = data.groups.firstIndex(where: { $0.id == groupID }) else { return }
            data.groups[index].name = payload.name
        case RecordType.habit:
            guard var habit = try? decoder.decode(Habit.self, from: json) else { return }
            habit.groupID = groupID
            if let index = data.habits.firstIndex(where: { $0.id == habit.id }) {
                data.habits[index] = habit
            } else {
                data.habits.append(habit)
            }
        case RecordType.checkIn:
            guard let key = checkInKey(fromName: name),
                  let checkIn = try? decoder.decode(CheckIn.self, from: json) else { return }
            data.checkIns[key] = checkIn
        default:
            break
        }
    }

    private static func remove(name: String, groupID: UUID, from data: inout AppData) {
        if name.hasPrefix("habit-"), let id = UUID(uuidString: String(name.dropFirst("habit-".count))) {
            guard data.habits.first(where: { $0.id == id })?.groupID == groupID else { return }
            data.habits.removeAll { $0.id == id }
            data.removeCheckIns(for: id)
        } else if name.hasPrefix("check-"), let key = checkInKey(fromName: name) {
            data.checkIns[key] = nil
        }
    }

    // MARK: Состояние синхронизации

    private struct ZoneState: Codable {
        /// CKServerChangeToken в архиве.
        var token: Data?
        /// JSON каждой записи на момент последней синхронизации.
        var synced: [String: Data] = [:]
    }

    private static let statesKey = "familySyncStates"

    private static func stateKey(_ zoneID: CKRecordZone.ID) -> String {
        zoneID.zoneName + "|" + zoneID.ownerName
    }

    private static func loadStates() -> [String: ZoneState] {
        guard let data = UserDefaults.standard.data(forKey: statesKey),
              let states = try? JSONDecoder().decode([String: ZoneState].self, from: data) else { return [:] }
        return states
    }

    private func saveStates() {
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: Self.statesKey)
        }
    }

    private static func archiveToken(_ token: CKServerChangeToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private static func unarchiveToken(_ data: Data) -> CKServerChangeToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    // MARK: Ошибки

    enum FamilyError: LocalizedError {
        case groupNotFound
        case noAccount
        case noLink

        var errorDescription: String? {
            switch self {
            case .groupNotFound: return String(localized: "The group wasn't found.")
            case .noAccount: return String(localized: "Sign in to iCloud in Settings to share groups with your family.")
            case .noLink: return String(localized: "Couldn't create an invitation link. Try again later.")
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? CKError {
            switch error.code {
            case .notAuthenticated:
                return String(localized: "Sign in to iCloud in Settings to share groups with your family.")
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
                return String(localized: "No connection to iCloud. Changes will sync later.")
            case .quotaExceeded:
                return String(localized: "iCloud storage is full.")
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
