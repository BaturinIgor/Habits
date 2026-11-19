import SwiftUI

#if DEBUG
/// Каталог экранов для макетов (design/<версия>/screens).
/// Приложение запускается с `-uitest -design -design-screen <id>` и сразу показывает нужный экран,
/// шит или попап поверх настоящего приложения на демо-данных. Снимки делает DesignCatalogUITests.
/// Только в отладочной сборке.
enum DesignScreen: String, CaseIterable, Identifiable {
    // Вкладки
    case today, habits, stats, settings
    // Экраны внутри навигации
    case habitDetail, quitDetail, notifications, todayScreen, groups, groupDetail, appIcon, backup
    // Шиты
    case catalog, editorNew, editorEdit, editorTemplate, iconPicker, timer, recap, recapMonth, recapYear, moodJournal, moodEntry
    case profile, sparks, pet, paywall, paywallFeature, feedback, voice, note, whatsNew
    // Во весь экран
    case onboarding, words

    var id: String { rawValue }

    enum Kind { case tab(AppTab), push, sheet, cover }

    var kind: Kind {
        switch self {
        case .today: .tab(.today)
        case .habits: .tab(.habits)
        case .stats: .tab(.stats)
        case .settings: .tab(.settings)
        case .habitDetail, .quitDetail, .notifications, .todayScreen, .groups, .groupDetail, .appIcon, .backup: .push
        case .onboarding, .words: .cover
        default: .sheet
        }
    }

    /// Экран из аргументов запуска.
    static var requested: DesignScreen? {
        guard TestMode.has("-design") else { return nil }
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-design-screen"), index + 1 < args.count else { return nil }
        return DesignScreen(rawValue: args[index + 1])
    }

    static var isDark: Bool { TestMode.has("-design-dark") }

    /// Подменённая дата для карточек итогов на «Сегодня» (`-design-now yyyy-MM-dd`).
    static var now: Date? {
        guard TestMode.has("-design") else { return nil }
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-design-now"), index + 1 < args.count else { return nil }
        let parts = args[index + 1].split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let date = Calendar.app.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 10))
        return date
    }

    @MainActor @ViewBuilder
    func content() -> some View {
        switch self {
        case .habitDetail: HabitDetailView(habitID: UITestSupport.id(1))
        case .quitDetail: HabitDetailView(habitID: UITestSupport.id(7))
        case .notifications: NotificationSettingsView()
        case .todayScreen: TodayScreenSettingsView()
        case .groups: GroupsView()
        case .groupDetail: GroupDetailView(groupID: DesignGallery.groupID)
        case .appIcon: AppIconView()
        case .backup: BackupSettingsView()
        case .catalog: HabitCatalogView()
        case .editorNew: HabitEditorView(habit: nil)
        case .editorEdit: DesignGallery.Editor(id: UITestSupport.id(1))
        case .editorTemplate: DesignGallery.TemplateEditor()
        case .iconPicker: DesignGallery.IconPicker()
        case .timer: DesignGallery.TimerSheet()
        case .recap: DesignGallery.RecapSheet(period: .week)
        case .recapMonth: DesignGallery.RecapSheet(period: .month)
        case .recapYear: DesignGallery.RecapSheet(period: .year)
        case .moodJournal: MoodJournalView()
        case .moodEntry: MoodEntryEditor(dayKey: DayKey.make(Date()))
        case .profile: ProfileView()
        case .sparks: SparksView()
        case .pet: PetView()
        case .paywall: PaywallView()
        case .paywallFeature: PaywallView(highlight: .health)
        case .feedback: FeedbackView()
        case .voice: VoiceHabitSheet { _ in }
        case .note: NoteEditorView(target: NoteTarget(habitID: UITestSupport.id(1), day: DayKey.make(Date())))
        case .whatsNew: WhatsNewView {}
        case .onboarding: OnboardingView()
        case .words: WordsSessionView(habitID: UITestSupport.id(8))
        case .today, .habits, .stats, .settings: EmptyView()
        }
    }
}

enum DesignGallery {
    static let groupID = UITestSupport.id(100)

    /// Дополняет демо-данные всем, что нужно для макетов: настроение, группы, питомец, слова.
    static func enrich(_ data: inout AppData, day: (Int) -> Date, start: Date, ru: Bool) {
        // Группы, одна общая с семьёй.
        let morning = HabitGroup(id: groupID, name: ru ? "Утро" : "Morning", sortOrder: 0)
        var family = HabitGroup(id: UITestSupport.id(101), name: ru ? "Семья" : "Family", sortOrder: 1)
        family.family = FamilyShare(zoneName: "design", ownerName: ru ? "Анна" : "Anna", isOwner: true, url: nil)
        data.groups = [morning, family]
        for index in data.habits.indices where [1, 3].contains(index + 1) {
            data.habits[index].groupID = groupID
        }

        // Изучение слов.
        var words = HabitCatalog.words("es")
        words.id = UITestSupport.id(8)
        words.createdAt = start
        words.schedule.startDate = start
        words.sortOrder = 8
        data.habits.append(words)

        // Настроение за две недели с заметками.
        let notes = ru
            ? ["Отличная тренировка", "Плохо спал", "Встреча с друзьями", nil]
            : ["Great workout", "Slept badly", "Dinner with friends", nil]
        for offset in -14 ... -1 {
            let level = [4, 3, 5, 2, 4, 4, 3][(offset + 14) % 7]
            data.moods[DayKey.make(day(offset))] = MoodEntry(level: level, note: notes[(offset + 14) % 4], updatedAt: day(offset))
        }

        // Длинная история (с начала прошлого года), чтобы итоги месяца и года были как у живого пользователя.
        let calendar = Calendar.app
        let historyStart = day(-700)
        let monthly = [74, 80, 86, 79, 88, 91, 72, 68, 83, 87, 92, 81]
        for index in data.habits.indices where data.habits[index].quit == nil && data.habits[index].id != words.id {
            data.habits[index].createdAt = historyStart
            data.habits[index].schedule.startDate = historyStart
        }
        let tracked = data.habits.filter { $0.quit == nil && $0.id != words.id }
        for offset in -700 ... -31 {
            let date = day(offset)
            let month = calendar.component(.month, from: date)
            for (n, habit) in tracked.enumerated() where habit.isScheduled(on: date) {
                // Спортзал 3 раза в неделю: через день.
                if habit.schedule.kind == .weekly, offset % 2 == 0 { continue }
                let roll = abs((offset &* 37 &+ n &* 101 &+ month &* 13) % 100)
                if roll < monthly[month - 1] {
                    data.setStatus(.done, habitID: habit.id, day: DayKey.make(date))
                }
            }
        }

        // Питомец.
        if TestMode.has("-design-nopet") { return }
        var pet = PetState(species: "cat", name: ru ? "Барсик" : "Whiskers", adoptedAt: day(-20))
        for offset in -20 ... -1 { pet.feeds[DayKey.make(day(offset))] = 2 }
        data.wallet.pet = pet
    }

    /// Шит редактора для существующей привычки.
    struct Editor: View {
        @Environment(HabitStore.self) private var store
        let id: UUID
        var body: some View {
            if let habit = store.habit(id) { HabitEditorView(habit: habit) }
        }
    }

    struct TemplateEditor: View {
        var body: some View {
            if let template = HabitCatalog.categories(isPro: true).dropFirst().first?.items.first?.habit {
                HabitEditorView(template: template)
            }
        }
    }

    struct IconPicker: View {
        @State private var icon: HabitIcon = .symbol("figure.run")
        var body: some View {
            NavigationStack { IconPickerView(icon: $icon, color: Palette.color(0)) }
        }
    }

    struct TimerSheet: View {
        @Environment(HabitStore.self) private var store
        var body: some View {
            if let habit = store.habit(UITestSupport.id(3)) { HabitTimerView(habit: habit) }
        }
    }

    struct RecapSheet: View {
        @Environment(HabitStore.self) private var store
        let period: Recap.Period
        var body: some View {
            RecapView(recap: Recap.current(period, in: store.data))
        }
    }
}

/// Показывает экран из `-design-screen` поверх приложения так же, как его показывает само приложение.
struct DesignGalleryPresenter: ViewModifier {
    @Binding var selection: AppTab
    @State private var sheet: DesignScreen?
    @State private var cover: DesignScreen?
    @State private var push: DesignScreen?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let push {
                    NavigationStack { push.content() }
                        .background(Color(.systemBackground).ignoresSafeArea())
                        .accessibilityIdentifier("design.ready")
                }
            }
            .sheet(item: $sheet) { screen in
                screen.content().accessibilityIdentifier("design.ready")
            }
            .fullScreenCover(item: $cover) { screen in
                screen.content().accessibilityIdentifier("design.ready")
            }
            .task {
                guard let screen = DesignScreen.requested else { return }
                if DesignScreen.isDark {
                    // Тёмная тема на всё окно, включая шиты и попапы.
                    for scene in UIApplication.shared.connectedScenes {
                        (scene as? UIWindowScene)?.windows.forEach { $0.overrideUserInterfaceStyle = .dark }
                    }
                }
                switch screen.kind {
                case let .tab(tab): selection = tab
                case .push: push = screen
                case .sheet:
                    try? await Task.sleep(for: .milliseconds(300))
                    sheet = screen
                case .cover:
                    try? await Task.sleep(for: .milliseconds(300))
                    cover = screen
                }
            }
    }
}
#endif

extension View {
    /// Для макетов: с аргументами `-uitest -design -design-alert <name>` сам открывает попап экрана.
    /// В сборке для App Store ничего не делает.
    @ViewBuilder
    func designAlert(_ name: String, _ isPresented: Binding<Bool>) -> some View {
        #if DEBUG
        task {
            guard TestMode.has("-design"), DesignAlert.requested == name else { return }
            try? await Task.sleep(for: .milliseconds(900))
            isPresented.wrappedValue = true
        }
        #else
        self
        #endif
    }
}

#if DEBUG
enum DesignAlert {
    static var requested: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-design-alert"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}
#endif
