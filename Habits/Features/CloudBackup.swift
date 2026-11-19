import CloudKit
import CryptoKit
import Foundation
import Observation
import UIKit

/// Автоматическая резервная копия в личном iCloud.
///
/// Одна запись Backup в приватной базе CloudKit (зона по умолчанию) с файлом копии
/// в том же формате, что и «Экспорт данных». Копия обновляется, когда приложение уходит
/// в фон или обновляется в фоне, если данные изменились и с прошлой копии прошло хотя бы
/// несколько минут. На новом телефоне её предлагают вернуть на первом экране, а ещё
/// это можно сделать в Настройки -> Резервная копия.
///
/// Тип записи Backup нужно добавить в схему (workflow CloudKit schema) и выкатить в Production.
@MainActor
@Observable
final class CloudBackup {
    static let shared = CloudBackup()

    /// iCloud есть только у сборки для App Store (те же права, что у семейных групп).
    static var isAvailable: Bool { FamilySync.isAvailable }

    /// Что лежит в iCloud.
    struct Info: Equatable {
        let date: Date
        let device: String
        let habits: Int
    }

    private(set) var isWorking = false
    private(set) var lastError: String?
    /// Дата последней успешной копии с этого телефона.
    private(set) var lastBackup: Date?

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }

    private enum Keys {
        static let enabled = "cloudBackupEnabled"
        static let last = "cloudBackupLast"
        static let hash = "cloudBackupHash"
    }

    private static let recordType = "Backup"
    private static let recordID = CKRecord.ID(recordName: "latest")
    /// Не чаще, чем раз в столько, даже если данные меняются.
    private static let minInterval: TimeInterval = 10 * 60

    @ObservationIgnored private lazy var container: CKContainer = {
        let id = Bundle.main.object(forInfoDictionaryKey: "CloudKitContainer") as? String ?? ""
        return CKContainer(identifier: id)
    }()

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        lastBackup = defaults.object(forKey: Keys.last) as? Date
    }

    // MARK: Сохранение

    /// Копия, если включена, данные изменились и прошло достаточно времени.
    func backupIfNeeded() async {
        guard Self.isAvailable, isEnabled, !isWorking else { return }
        let store = HabitStore.shared
        // Пустые данные не сохраняем: иначе свежая установка затёрла бы старую копию.
        guard !store.data.habits.isEmpty else { return }
        if let lastBackup, Date().timeIntervalSince(lastBackup) < Self.minInterval { return }
        let payload = store.exportData()
        guard Self.hash(payload) != UserDefaults.standard.string(forKey: Keys.hash) else { return }
        try? await upload(payload, habits: store.data.habits.count)
    }

    /// Кнопка «Сохранить сейчас».
    func backupNow() async {
        guard Self.isAvailable, !isWorking else { return }
        let store = HabitStore.shared
        guard !store.data.habits.isEmpty else { return }
        try? await upload(store.exportData(), habits: store.data.habits.count)
    }

    /// Копия при уходе в фон: просим у системы время, чтобы загрузка успела закончиться.
    func backupBeforeBackground() {
        guard Self.isAvailable, isEnabled else { return }
        let app = UIApplication.shared
        var taskID = UIBackgroundTaskIdentifier.invalid
        taskID = app.beginBackgroundTask(withName: "CloudBackup") {
            if taskID != .invalid {
                app.endBackgroundTask(taskID)
                taskID = .invalid
            }
        }
        Task {
            await backupIfNeeded()
            if taskID != .invalid {
                app.endBackgroundTask(taskID)
                taskID = .invalid
            }
        }
    }

    private func upload(_ payload: Data, habits: Int) async throws {
        isWorking = true
        defer { isWorking = false }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("zenhab-backup-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            guard try await container.accountStatus() == .available else { throw BackupError.noAccount }
            try payload.write(to: file, options: .atomic)
            let database = container.privateCloudDatabase
            // Берём существующую запись, чтобы перезаписать её, а не получить конфликт.
            let record: CKRecord
            if let existing = try? await database.record(for: Self.recordID) {
                record = existing
            } else {
                record = CKRecord(recordType: Self.recordType, recordID: Self.recordID)
            }
            record["file"] = CKAsset(fileURL: file)
            record["habits"] = habits as CKRecordValue
            record["device"] = UIDevice.current.name as CKRecordValue
            record["savedAt"] = Date() as CKRecordValue
            let (results, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            if case .failure(let error)? = results[Self.recordID] { throw error }
            let now = Date()
            lastBackup = now
            lastError = nil
            UserDefaults.standard.set(now, forKey: Keys.last)
            UserDefaults.standard.set(Self.hash(payload), forKey: Keys.hash)
        } catch {
            lastError = Self.describe(error)
            throw error
        }
    }

    // MARK: Восстановление

    /// Копия в iCloud или nil, если её нет.
    func fetchLatest() async throws -> (info: Info, data: AppData)? {
        guard Self.isAvailable else { return nil }
        guard try await container.accountStatus() == .available else { return nil }
        let record: CKRecord
        do {
            record = try await container.privateCloudDatabase.record(for: Self.recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
        guard let url = (record["file"] as? CKAsset)?.fileURL,
              let raw = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? decoder.decode(AppData.self, from: raw) else { return nil }
        let info = Info(
            date: record["savedAt"] as? Date ?? record.modificationDate ?? Date(),
            device: record["device"] as? String ?? "",
            habits: (record["habits"] as? Int) ?? data.habits.count
        )
        return (info, data)
    }

    /// Заменяет данные на телефоне копией из iCloud.
    func restore(_ data: AppData) {
        Analytics.shared.send(.backupRestored)
        HabitStore.shared.replaceAll(with: data)
        // Только что вернули эти данные: заново их не загружаем.
        UserDefaults.standard.set(Self.hash(HabitStore.shared.exportData()), forKey: Keys.hash)
    }

    // MARK: Вспомогательное

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    enum BackupError: LocalizedError {
        case noAccount

        var errorDescription: String? {
            String(localized: "Sign in to iCloud in Settings to keep a backup.")
        }
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? BackupError { return error.localizedDescription }
        if let error = error as? CKError {
            switch error.code {
            case .notAuthenticated:
                return String(localized: "Sign in to iCloud in Settings to keep a backup.")
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
                return String(localized: "No connection to iCloud. The backup will be saved later.")
            case .quotaExceeded:
                return String(localized: "iCloud storage is full.")
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
