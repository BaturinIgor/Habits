import Foundation

/// Цель первого запуска (1.7, KAN-121): под каждую готовая программа из привычек каталога.
enum OnboardingGoal: String, CaseIterable, Identifiable {
    case energy, calm, fitness, learning, sleep, focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .energy: String(localized: "Energy")
        case .calm: String(localized: "Calm")
        case .fitness: String(localized: "Fitness")
        case .learning: String(localized: "Learning and languages")
        case .sleep: String(localized: "Better sleep")
        case .focus: String(localized: "Focus")
        }
    }

    var subtitle: String {
        switch self {
        case .energy: String(localized: "Water, movement and fresh air")
        case .calm: String(localized: "Less stress, more balance")
        case .fitness: String(localized: "Workouts and an active day")
        case .learning: String(localized: "Reading, study and new words")
        case .sleep: String(localized: "A calm evening and a steady routine")
        case .focus: String(localized: "Plan the day and get things done")
        }
    }

    var symbol: String {
        switch self {
        case .energy: "bolt.fill"
        case .calm: "leaf.fill"
        case .fitness: "figure.run"
        case .learning: "graduationcap.fill"
        case .sleep: "moon.stars.fill"
        case .focus: "checklist"
        }
    }

    var colorIndex: Int {
        switch self {
        case .energy: 1
        case .calm: 4
        case .fitness: 0
        case .learning: 6
        case .sleep: 7
        case .focus: 3
        }
    }

    /// id привычек каталога (HabitCatalog) в порядке показа. «words» — изучение слов на предложенном языке.
    var itemIDs: [String] {
        switch self {
        case .energy: ["water", "exercises", "outside", "sleep"]
        case .calm: ["meditate", "breathe", "gratitude", "nophone"]
        case .fitness: ["workout", "steps", "stretch", "water"]
        case .learning: ["read", "words", "study", "podcast"]
        case .sleep: ["sleep", "nophone", "stretch", "journal"]
        case .focus: ["plan", "focus", "bed", "tidy"]
        }
    }
}

/// Что онбординг создаёт и когда его показывать.
enum OnboardingPlan {
    /// Шаги для статистики (onboarding_step): номер = rawValue.
    enum Step: Int, CaseIterable {
        case goal = 1, habits, summary, paywall
    }

    /// Привычки программы цели: готовые к добавлению копии из каталога с новыми id.
    static func habits(for goal: OnboardingGoal, isPro: Bool) -> [Habit] {
        let items = HabitCatalog.categories(isPro: isPro).flatMap(\.items)
        return goal.itemIDs.compactMap { id in
            let itemID = id == "words" ? "words-" + WordLanguage.suggested : id
            guard var habit = items.first(where: { $0.id == itemID })?.habit else { return nil }
            habit.id = UUID()
            habit.createdAt = Date()
            return habit
        }
    }

    /// Какие из выбранных привычек добавить: без тех, что уже есть (повторный показ из настроек),
    /// и не больше лимита бесплатной версии.
    static func habitsToAdd(_ selected: [Habit], to data: AppData) -> [Habit] {
        var result: [Habit] = []
        var active = data.activeHabits.count
        for habit in selected where !contains(habit, in: data.activeHabits + result) {
            guard data.isPro || active < AppData.freeHabitLimit else { break }
            result.append(habit)
            active += 1
        }
        return result
    }

    /// Сколько ещё привычек можно выбрать в бесплатной версии.
    static func freeSlots(in data: AppData) -> Int? {
        data.isPro ? nil : max(0, AppData.freeHabitLimit - data.activeHabits.count)
    }

    /// Онбординг только на первом запуске: у обновившихся со старой версии onboardingDone уже true.
    static func shouldShowOnboarding(_ settings: AppSettings) -> Bool {
        !settings.onboardingDone
    }

    /// Пейволл в конце онбординга (KAN-122): один раз и только без Pro.
    static func shouldShowPaywall(_ data: AppData) -> Bool {
        !data.isPro && !data.settings.onboardingPaywallSeen
    }

    /// Подсказки первого дня на «Сегодня» (KAN-169): только если онбординг создал привычки
    /// и отметок ещё не было (не повторный показ знакомства).
    static func startsFirstDay(created: Int, data: AppData) -> Bool {
        created > 0 && !data.checkIns.values.contains { $0.status == .done }
    }

    /// Состояние «первого дня» на «Сегодня».
    enum FirstDay: Equatable {
        /// Подсказка: отметь первую привычку.
        case hint
        /// Первая отметка сделана: поздравление и предложение включить напоминания.
        case celebrate
    }

    static func firstDay(_ data: AppData) -> FirstDay? {
        guard data.settings.firstDayGuide else { return nil }
        return data.checkIns.values.contains { $0.status == .done } ? .celebrate : .hint
    }

    private static func contains(_ habit: Habit, in habits: [Habit]) -> Bool {
        habits.contains { existing in
            if let language = habit.wordsLanguage { return existing.wordsLanguage == language }
            return existing.name.caseInsensitiveCompare(habit.name) == .orderedSame
        }
    }
}
