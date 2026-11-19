import Foundation
import OSLog
import WatchConnectivity

/// Связь с приложением на Apple Watch.
/// iPhone отправляет снимок привычек на сегодня и завтра, а часы присылают отметки.
/// Данные живут на iPhone: часы только показывают снимок и просят что-то отметить.
@MainActor
final class WatchSync: NSObject {
    static let shared = WatchSync()
    private static let log = Logger(subsystem: "com.personal.habits", category: "WatchSync")

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    /// Последний отправленный снимок без времени создания: не шлём одно и то же.
    private var lastSent: [WatchDay] = []
    private var lastSentAcks: [String: Date]?
    private var lastSentPro: Bool?
    /// Последний прогресс, отправленный в компликацию: у неё ограничен дневной запас обновлений.
    private var lastComplication: String?
    /// Отметки с часов, которые уже пришли: часы по ним понимают, что ждать больше нечего.
    /// Хранятся на диске, потому что iPhone может получить отметку в фоне и тут же выгрузиться.
    private var acks: [String: Date] = WatchSync.loadAcks()
    private static let acksKey = "watchMarkAcks"

    func start() {
        guard let session, session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    /// Отправить часам свежий снимок, если он изменился.
    func push(_ data: AppData, force: Bool = false) {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        let snapshot = snapshot(data)
        if !force && snapshot.days == lastSent && snapshot.isPro == lastSentPro && snapshot.acks == lastSentAcks { return }
        guard let raw = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try session.updateApplicationContext([WatchKeys.snapshot: raw])
            lastSent = snapshot.days
            lastSentPro = snapshot.isPro
            lastSentAcks = snapshot.acks
        } catch {
            Self.log.error("Watch context failed: \(error.localizedDescription, privacy: .public)")
        }
        // Компликацию будим отдельно, только когда меняется прогресс дня.
        let today = snapshot.days.first
        let progress = "\(today?.day ?? "")|\(today?.doneCount ?? 0)|\(today?.plannedCount ?? 0)"
        if session.isComplicationEnabled, progress != lastComplication,
           session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo([WatchKeys.snapshot: raw])
            lastComplication = progress
        }
    }

    /// Отметки с часов.
    private func receive(_ payload: [String: Any]) {
        guard let raw = payload[WatchKeys.mark] as? Data,
              let marks = try? JSONDecoder().decode([WatchMark].self, from: raw) else { return }
        let store = HabitStore.shared
        // Приложение могло быть не запущено: берём свежие данные с диска.
        store.reloadFromDisk()
        // Отметки из очереди могут прийти не по порядку: применяем от старых к новым.
        for mark in marks.sorted(by: { $0.at < $1.at }) {
            store.applyWatchMark(mark)
            if acks[mark.key].map({ $0 < mark.at }) ?? true {
                acks[mark.key] = mark.at
            }
        }
        saveAcks()
        // Даже если ничего не поменялось, часы должны получить подтверждение.
        push(store.data, force: true)
    }
}

extension WatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            WatchSync.shared.push(HabitStore.shared.data, force: true)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Пользователь сменил часы: подключаемся к новым.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            WatchSync.shared.push(HabitStore.shared.data, force: true)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let payload = Payload(message)
        let reply = ReplyBox(replyHandler)
        Task { @MainActor in
            WatchSync.shared.receive(payload.value)
            let snapshot = WatchSync.shared.snapshot(HabitStore.shared.data)
            if let raw = try? JSONEncoder().encode(snapshot) {
                reply.handler([WatchKeys.snapshot: raw])
            } else {
                reply.handler([:])
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let payload = Payload(userInfo)
        Task { @MainActor in
            WatchSync.shared.receive(payload.value)
        }
    }
}

// MARK: - Подтверждения отметок

extension WatchSync {
    func snapshot(_ data: AppData) -> WatchSnapshot {
        var snapshot = WatchSnapshot.make(from: data)
        snapshot.acks = currentAcks(for: snapshot)
        return snapshot
    }

    /// Подтверждения за последние дни: часы ждут их и для дней, которых уже нет в снимке
    /// (например, таймер закончился после полуночи). Более старые не нужны.
    fileprivate func currentAcks(for snapshot: WatchSnapshot) -> [String: Date] {
        let oldest = WatchDayKey.ackHorizon(before: snapshot.generatedAt)
        let fresh = acks.filter { key, _ in
            String(key.split(separator: "|").last ?? "") >= oldest
        }
        if fresh.count != acks.count {
            acks = fresh
            saveAcks()
        }
        return fresh
    }

    fileprivate static func loadAcks() -> [String: Date] {
        guard let raw = UserDefaults.standard.data(forKey: acksKey),
              let value = try? JSONDecoder().decode([String: Date].self, from: raw) else { return [:] }
        return value
    }

    fileprivate func saveAcks() {
        guard let raw = try? JSONEncoder().encode(acks) else { return }
        UserDefaults.standard.set(raw, forKey: Self.acksKey)
    }
}

/// Словари WatchConnectivity содержат только Data, поэтому их можно передать в главный поток.
private struct Payload: @unchecked Sendable {
    let value: [String: Any]
    init(_ value: [String: Any]) { self.value = value }
}

private struct ReplyBox: @unchecked Sendable {
    let handler: ([String: Any]) -> Void
    init(_ handler: @escaping ([String: Any]) -> Void) { self.handler = handler }
}

// MARK: - Снимок для часов

extension WatchSnapshot {
    @MainActor
    static func make(from data: AppData, now: Date = Date()) -> WatchSnapshot {
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        let days = [today, tomorrow].map { date -> WatchDay in
            let key = DayKey.make(date, calendar: calendar)
            let habits = data.habits(on: date, calendar: calendar)
                .filter { !$0.isQuit }
                .sortedForDisplay()
                .map { habit -> WatchHabit in
                    let status = data.status(habit.id, day: key)
                    var emoji: String?
                    var symbol: String?
                    switch habit.icon {
                    case .emoji(let value): emoji = value
                    case .symbol(let value): symbol = value
                    }
                    return WatchHabit(
                        id: habit.id,
                        name: habit.name,
                        emoji: emoji,
                        symbol: symbol,
                        colorIndex: habit.colorIndex,
                        target: habit.dailyTarget(isPro: data.isPro),
                        count: data.count(of: habit, day: key),
                        done: status == .done,
                        skipped: status == .skipped,
                        timerMinutes: habit.timerMinutes
                    )
                }
            return WatchDay(day: key, habits: habits)
        }
        return WatchSnapshot(generatedAt: now, isPro: data.isPro, days: days)
    }
}

// MARK: - Отметка с часов

extension AppData {
    /// Ставит привычке состояние, выбранное на часах.
    /// Возвращает false, если менять нечего или на iPhone отметили позже.
    /// Время отметки берётся с часов: так несколько отметок, пришедших пачкой после работы
    /// без связи, применяются по порядку и побеждает последняя, а не первая доставленная.
    mutating func applyWatchMark(_ mark: WatchMark) -> Bool {
        let k = Self.key(mark.habitID, mark.day)
        var entry = checkIns[k] ?? CheckIn(status: nil, note: nil, updatedAt: .distantPast)
        if entry.updatedAt > mark.at { return false }
        let target = habits.first(where: { $0.id == mark.habitID })?.dailyTarget(isPro: isPro) ?? 1
        if mark.done {
            // Как setStatus: повторная отметка не меняет время, чтобы не пропали искры за честную отметку.
            if entry.status == .done && entry.isMinimum != true { return false }
            entry.status = .done
            entry.count = nil
        } else {
            let count = min(max(0, mark.count), target)
            if entry.status == nil && (entry.count ?? 0) == count { return false }
            entry.status = nil
            entry.count = count > 0 ? count : nil
        }
        entry.isMinimum = nil
        // Часы могут спешить: время из будущего не ставим.
        entry.updatedAt = min(mark.at, Date())
        let hasNote = !(entry.note ?? "").isEmpty
        if entry.status == nil && !hasNote && (entry.count ?? 0) == 0 {
            checkIns[k] = nil
        } else {
            checkIns[k] = entry
        }
        return true
    }
}
