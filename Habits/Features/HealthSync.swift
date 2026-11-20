import Foundation
import HealthKit
import Observation

/// Автоотметка привычек по данным Apple Health (Pro).
///
/// Приложение только читает данные. Когда показатель за день дошёл до цели, привычка
/// отмечается выполненной; отметку никогда не снимаем сами. Проверяем сегодня и вчера
/// (сон и поздние шаги), при открытии приложения, при обновлении в фоне и по жесту «потянуть вниз».
///
/// HealthKit есть только в сборке для App Store: tools/appstore/enable_family.sh добавляет права
/// и ставит HealthEnabled. В сборке для SideStore раздел скрыт.
@MainActor
@Observable
final class HealthSync {
    static let shared = HealthSync()

    static var isAvailable: Bool {
        #if DEBUG
        // Макеты (DesignGallery) показывают раздел Apple Health и без прав HealthKit.
        if TestMode.has("-design") { return true }
        #endif
        return (Bundle.main.object(forInfoDictionaryKey: "HealthEnabled") as? Bool) == true
            && HKHealthStore.isHealthDataAvailable()
    }

    /// Последние значения за сегодня: id привычки -> значение показателя.
    private(set) var today: [UUID: Double] = [:]

    @ObservationIgnored private lazy var store = HKHealthStore()
    @ObservationIgnored private var isSyncing = false

    private init() {}

    // MARK: Разрешение

    private static func readTypes(_ metric: HealthLink.Metric) -> Set<HKObjectType> {
        switch metric {
        case .steps: [HKQuantityType(.stepCount)]
        case .exerciseMinutes: [HKQuantityType(.appleExerciseTime)]
        case .mindfulMinutes: [HKCategoryType(.mindfulSession)]
        case .sleepHours: [HKCategoryType(.sleepAnalysis)]
        case .water: [HKQuantityType(.dietaryWater)]
        case .workouts: [HKObjectType.workoutType()]
        }
    }

    /// Просит доступ к показателю. Apple не говорит, разрешил ли человек чтение,
    /// поэтому просто пробуем читать: без доступа значения будут нулевыми.
    func requestAccess(for metric: HealthLink.Metric) async {
        guard Self.isAvailable else { return }
        try? await store.requestAuthorization(toShare: [], read: Self.readTypes(metric))
    }

    // MARK: Синхронизация

    func sync() async {
        let habitStore = HabitStore.shared
        guard Self.isAvailable, habitStore.data.isPro, !isSyncing else { return }
        let linked = habitStore.data.activeHabits.filter { $0.health != nil && !$0.isQuit }
        guard !linked.isEmpty else {
            today = [:]
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        let calendar = Calendar.app
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        var fresh: [UUID: Double] = [:]
        for habit in linked {
            guard let link = habit.health else { continue }
            for offset in [-1, 0] {
                guard let day = calendar.date(byAdding: .day, value: offset, to: todayStart) else { continue }
                let value = await self.value(link.metric, on: day)
                if offset == 0 { fresh[habit.id] = value }
                guard habit.isScheduled(on: day), value >= link.goal else { continue }
                // Берём свежую отметку: человек мог отметить или пропустить вручную, пока шёл запрос.
                if habitStore.status(habit.id, on: day) == nil {
                    habitStore.setStatus(.done, for: habit.id, on: day)
                }
            }
        }
        today = fresh
    }

    // MARK: Чтение показателей

    func value(_ metric: HealthLink.Metric, on day: Date) async -> Double {
        let calendar = Calendar.app
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        switch metric {
        case .steps:
            return await sum(.stepCount, unit: .count(), from: start, to: end)
        case .exerciseMinutes:
            return await sum(.appleExerciseTime, unit: .minute(), from: start, to: end)
        case .water:
            return await sum(.dietaryWater, unit: .liter(), from: start, to: end)
        case .mindfulMinutes:
            let samples = await categorySamples(.mindfulSession, from: start, to: end)
            return Self.mergedDuration(samples) / 60
        case .sleepHours:
            // Сон, который закончился в этот день: ночь с 18:00 накануне до 18:00.
            let from = calendar.date(byAdding: .hour, value: -6, to: start) ?? start
            let to = calendar.date(byAdding: .hour, value: 18, to: start) ?? end
            let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
            let samples = await categorySamples(.sleepAnalysis, from: from, to: to)
                .filter { asleep.contains($0.value) }
            return Self.mergedDuration(samples) / 3600
        case .workouts:
            return Double(await workoutCount(from: start, to: end))
        }
    }

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: .cumulativeSum
        )
        let result = try? await descriptor.result(for: store)
        return result?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    private func categorySamples(_ id: HKCategoryTypeIdentifier, from start: Date, to end: Date) async -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(id), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return (try? await descriptor.result(for: store)) ?? []
    }

    private func workoutCount(from start: Date, to end: Date) async -> Int {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: []
        )
        return ((try? await descriptor.result(for: store)) ?? []).count
    }

    /// Суммарная длительность без двойного счёта: часы и телефон пишут сон одновременно.
    private static func mergedDuration(_ samples: [HKCategorySample]) -> TimeInterval {
        let sorted = samples.sorted { $0.startDate < $1.startDate }
        var total: TimeInterval = 0
        var current: (start: Date, end: Date)?
        for sample in sorted {
            if let range = current, sample.startDate <= range.end {
                current = (range.start, max(range.end, sample.endDate))
            } else {
                if let range = current { total += range.end.timeIntervalSince(range.start) }
                current = (sample.startDate, sample.endDate)
            }
        }
        if let range = current { total += range.end.timeIntervalSince(range.start) }
        return total
    }
}
