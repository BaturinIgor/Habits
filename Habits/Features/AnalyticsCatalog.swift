import Foundation

// Все имена, которые уходят в статистику (Firebase). Новые экраны и действия добавляйте сюда:
// так в статистику не попадёт ничего личного (названий привычек, заметок, текста).
// Имена переводятся в формат Firebase: "Habit.check" -> "habit_check". У Firebase лимит 500 разных
// событий на приложение и 25 параметров на событие, поэтому не создавайте имена на лету.

/// Экраны приложения: уходят как screen_view с этим именем.
enum AnalyticsScreen: String, CaseIterable {
    case today = "Today"
    case habits = "Habits"
    case stats = "Stats"
    case settings = "Settings"
    case onboarding = "Onboarding"
    case whatsNew = "WhatsNew"
    case profile = "Profile"
    case sparks = "Sparks"
    case pet = "Pet"
    case catalog = "Catalog"
    case editor = "Editor"
    case voiceHabit = "VoiceHabit"
    case iconPicker = "IconPicker"
    case detail = "Detail"
    case noteEditor = "NoteEditor"
    case timer = "Timer"
    case words = "Words"
    case weeklyRecap = "WeeklyRecap"
    case monthlyRecap = "MonthlyRecap"
    case yearlyRecap = "YearlyRecap"
    case moodEditor = "MoodEditor"
    case moodJournal = "MoodJournal"
    case paywall = "Paywall"
    case feedback = "Feedback"
    case notificationSettings = "NotificationSettings"
    case todaySettings = "TodaySettings"
    case backupSettings = "BackupSettings"
    case healthSettings = "HealthSettings"
    case groups = "Groups"
    case groupDetail = "GroupDetail"
    case appIcon = "AppIcon"
}

/// Действия пользователя: каждое уходит своим событием с параметром screen.
enum AnalyticsAction: String, CaseIterable {
    // Отметки
    case check = "Habit.check"
    case uncheck = "Habit.uncheck"
    case minimum = "Habit.minimum"
    case skip = "Habit.skip"
    case clearStatus = "Habit.clearStatus"
    case decrement = "Habit.decrement"
    /// +1 у привычки со счётчиком, цель ещё не достигнута.
    case increment = "Habit.increment"
    case checkPastDay = "Habit.checkPastDay"
    case checkFromNotification = "Notification.done"
    case skipFromNotification = "Notification.skip"
    case checkFromWatch = "Watch.check"
    case uncheckFromWatch = "Watch.uncheck"
    // Привычки
    case edit = "Habit.edit"
    case archive = "Habit.archive"
    case unarchive = "Habit.unarchive"
    case reorder = "Habit.reorder"
    case relapse = "Quit.relapse"
    case noteSave = "Note.save"
    // Искры и питомец
    case rewardBuy = "Shop.reward"
    case freezeBuy = "Shop.freeze"
    case streakRepair = "Shop.streakRepair"
    case petFeed = "Pet.feed"
    case petRename = "Pet.rename"
    case petSpecies = "Pet.species"
    // Группы
    case groupAdd = "Group.add"
    case groupRename = "Group.rename"
    case groupDelete = "Group.delete"
    case groupReorder = "Group.reorder"
    // Настроение и слова
    case moodSet = "Mood.set"
    case moodRemove = "Mood.remove"
    case wordKnown = "Words.known"
    case wordUnknown = "Words.unknown"
    // Данные
    case exportJSON = "Data.exportJSON"
    case exportCSV = "Data.exportCSV"
    case importData = "Data.import"
    // Прочее
    case settingsChange = "Settings.change"
    case recapShare = "Recap.share"
    case familyInviteShare = "Family.inviteShare"
    case timerStart = "Timer.start"
    case appIconChange = "AppIcon.change"
    case paywallClose = "Paywall.close"
    case restoreTap = "Paywall.restore"
}

/// Какое действие отметки отправить, по состоянию до и после.
enum AnalyticsCheck {
    /// Нажатие на кружок (AppData.tap): выполнено, снято, +1 к счётчику или ничего.
    static func tap(before: CheckStatus?, after: CheckStatus?, countBefore: Int, countAfter: Int) -> AnalyticsAction? {
        if after == .done && before != .done { return .check }
        if before == .done && after != .done { return .uncheck }
        if countAfter > countBefore { return .increment }
        return nil
    }

    /// Явная установка статуса (меню, отметка за прошлый день). Тот же статус ещё раз ничего не меняет.
    static func set(before: CheckStatus?, after: CheckStatus?) -> AnalyticsAction? {
        guard before != after else { return nil }
        switch after {
        case .done: return .check
        case nil: return .clearStatus
        default: return .skip
        }
    }
}

/// Откуда создана привычка.
enum HabitSource: String {
    case editor, catalog, siri, onboarding
}

/// Важные события с параметрами.
enum AnalyticsEvent {
    case appInstalled(isUpdate: Bool)
    case onboardingCompleted(seconds: Int, restoredFromCloud: Bool)
    case habitCreated(Habit, source: HabitSource)
    case habitDeleted(ageDays: Int, isQuit: Bool)
    case paywallShown(source: String)
    case purchaseStarted(product: String, source: String)
    case purchaseCompleted(product: String, source: String)
    case purchaseCancelled(product: String, source: String)
    case purchaseFailed(product: String, source: String)
    case restoreFinished(found: Bool)
    case proChanged(active: Bool)
    case petAdopted(species: String)
    case petStageReached(stage: Int)
    case achievementUnlocked(id: String)
    case ratingPromptShown
    case familyGroupCreated
    case familyGroupJoined
    case feedbackSent(channel: String)
    case backupRestored

    var type: String {
        switch self {
        case .appInstalled: "App.installed"
        case .onboardingCompleted: "Onboarding.completed"
        case .habitCreated: "Habit.created"
        case .habitDeleted: "Habit.deleted"
        case .paywallShown: "Paywall.shown"
        case .purchaseStarted: "Purchase.started"
        case .purchaseCompleted: "Purchase.completed"
        case .purchaseCancelled: "Purchase.cancelled"
        case .purchaseFailed: "Purchase.failed"
        case .restoreFinished: "Purchase.restored"
        case .proChanged: "Pro.changed"
        case .petAdopted: "Pet.adopted"
        case .petStageReached: "Pet.stageReached"
        case .achievementUnlocked: "Achievement.unlocked"
        case .ratingPromptShown: "Rating.promptShown"
        case .familyGroupCreated: "Family.groupCreated"
        case .familyGroupJoined: "Family.groupJoined"
        case .feedbackSent: "Feedback.sent"
        case .backupRestored: "Backup.restored"
        }
    }

    var floatValue: Double? {
        switch self {
        case .onboardingCompleted(let seconds, _): Double(seconds)
        case .habitDeleted(let age, _): Double(age)
        default: nil
        }
    }

    var payload: [String: Any] {
        switch self {
        case .appInstalled(let isUpdate):
            return ["App.isUpdate": isUpdate]
        case .onboardingCompleted(let seconds, let restored):
            return ["Onboarding.seconds": seconds, "Onboarding.restoredFromCloud": restored]
        case .habitCreated(let habit, let source):
            var iconKind = "other"
            if case .symbol = habit.icon { iconKind = "symbol" }
            return [
                "Habit.source": source.rawValue,
                "Habit.schedule": habit.schedule.kind.rawValue,
                "Habit.isQuit": habit.isQuit,
                "Habit.isWords": habit.isWords,
                "Habit.hasReminder": habit.reminder != nil,
                "Habit.hasGoal": habit.target != nil,
                "Habit.hasHealth": habit.health != nil,
                "Habit.hasTimer": habit.timerMinutes != nil,
                "Habit.hasMinimum": habit.minimumVersion != nil,
                "Habit.hasChain": habit.chainAfter != nil,
                "Habit.partOfDay": habit.partOfDay?.rawValue ?? "none",
                "Habit.iconKind": iconKind,
            ]
        case .habitDeleted(let age, let isQuit):
            return ["Habit.ageDays": age, "Habit.isQuit": isQuit]
        case .paywallShown(let source):
            return ["Paywall.source": source]
        case .purchaseStarted(let product, let source),
             .purchaseCompleted(let product, let source),
             .purchaseCancelled(let product, let source),
             .purchaseFailed(let product, let source):
            return ["Purchase.product": product, "Paywall.source": source]
        case .restoreFinished(let found):
            return ["Purchase.found": found]
        case .proChanged(let active):
            return ["Pro.active": active]
        case .petAdopted(let species):
            return ["Pet.species": species]
        case .petStageReached(let stage):
            return ["Pet.stage": stage]
        case .achievementUnlocked(let id):
            return ["Achievement.id": id]
        case .feedbackSent(let channel):
            return ["Feedback.channel": channel]
        case .ratingPromptShown, .familyGroupCreated, .familyGroupJoined, .backupRestored:
            return [:]
        }
    }
}

/// Состояние приложения раз в день (событие daily_state): только числа и флаги, не больше 24 ключей.
enum AnalyticsSnapshot {
    static func make(_ data: AppData) -> [String: Any] {
        let active = data.activeHabits
        let today = Date()
        let calendar = Calendar.app
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today).map { DayKey.make($0) } ?? ""
        let todayKey = DayKey.make(today)
        // Отметки за 7 дней: прямой поиск по ключам вместо обхода всей истории (её бывают десятки тысяч).
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: today).map { DayKey.make($0) } }
        var checks7 = 0
        for habit in data.habits {
            for day in days where data.checkIns[AppData.key(habit.id, day)]?.status == .done { checks7 += 1 }
        }
        let moods7 = data.moods.keys.filter { $0 > weekAgo && $0 <= todayKey }.count
        let pet = data.wallet.pet
        return [
            "State.habits": active.count,
            "State.archived": data.habits.count - active.count,
            "State.quitHabits": active.filter(\.isQuit).count,
            "State.wordsHabits": active.filter(\.isWords).count,
            "State.healthHabits": active.filter { $0.health != nil }.count,
            "State.timerHabits": active.filter { $0.timerMinutes != nil }.count,
            "State.reminderHabits": active.filter { $0.reminder != nil }.count,
            "State.groups": data.groups.count,
            "State.familyGroups": data.groups.filter { $0.family != nil }.count,
            "State.checks7d": checks7,
            "State.moods7d": moods7,
            "State.hasPet": pet != nil,
            "State.petSpecies": pet?.species ?? "none",
            // Стадия из уже запомненных (syncPetStage), без пересчёта опыта по всей истории.
            "State.petStage": pet.map { ($0.highestReached ?? .egg).rawValue } ?? -1,
            "State.achievements": data.settings.seenAchievements.count,
            "State.remindersOn": data.settings.remindersEnabled,
            "State.summaryOn": data.settings.summaryEnabled,
            "State.layout": data.settings.homeLayout.rawValue,
            "State.appLock": data.settings.appLock,
            "State.moodCard": data.settings.moodCard,
            "State.avatar": data.settings.avatarID,
            "State.background": data.settings.backgroundID,
        ]
    }
}
