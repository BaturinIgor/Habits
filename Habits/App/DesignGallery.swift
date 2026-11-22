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
    case habitDetail, quitDetail, smartSuggestion, notifications, todayScreen, groups, groupDetail, appIcon, backup, healthSettings
    // Шиты
    case catalog, editorNew, editorEdit, editorTemplate, iconPicker, timer, recap, moodJournal, moodEntry
    case editorHealth, smartEditor, smartEditorOff, profile, sparks, pet, petSwitched, petNaming, petSpecies, paywall, paywallFeature, feedback, voice, note, whatsNew
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
        case .habitDetail, .quitDetail, .smartSuggestion, .notifications, .todayScreen, .groups, .groupDetail, .appIcon, .backup, .healthSettings: .push
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
        // 1.6, App Review 2.5.1: интеграция с Apple Health видна в интерфейсе.
        case .healthSettings: HealthSettingsView(scrollToLinked: true)
        case .editorHealth: DesignGallery.HealthEditor()
        // 1.7, KAN-135: умное время напоминаний.
        case .smartSuggestion: HabitDetailView(habitID: UITestSupport.id(1))
        case .smartEditor, .smartEditorOff: DesignGallery.ReminderEditor(id: UITestSupport.id(1))
        case .catalog: HabitCatalogView()
        case .editorNew: HabitEditorView(habit: nil)
        case .editorEdit: DesignGallery.Editor(id: UITestSupport.id(1))
        case .editorTemplate: DesignGallery.TemplateEditor()
        case .iconPicker: DesignGallery.IconPicker()
        case .timer: DesignGallery.TimerSheet()
        case .recap: DesignGallery.RecapScreen()
        case .moodJournal: MoodJournalView()
        case .moodEntry: MoodEntryEditor(dayKey: DayKey.make(Date()))
        case .profile: ProfileView()
        case .sparks: SparksView()
        case .pet: PetView()
        // 1.6, KAN-105: своё имя у каждого вида питомца.
        case .petSwitched, .petNaming: PetView()
        case .petSpecies: PetView(scrollToSpecies: true)
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

        // Питомец.
        var pet = PetState(species: "cat", name: ru ? "Барсик" : "Whiskers", adoptedAt: day(-20))
        for offset in -20 ... -1 { pet.feeds[DayKey.make(day(offset))] = 2 }
        data.wallet.pet = pet

        // 1.7, KAN-135: зарядку обычно отмечают около 8:40, а напоминание в 7:30 - предложение сдвинуть.
        if [.smartSuggestion, .smartEditor, .smartEditorOff].contains(DesignScreen.requested) {
            let calendar = Calendar.app
            for offset in -21 ... -2 {
                let key = DayKey.make(day(offset))
                let minute = [35, 40, 45, 40, 50, 38, 42][(offset + 21) % 7]
                guard var checkIn = data.checkIns[AppData.key(UITestSupport.id(1), key)],
                      let time = calendar.date(bySettingHour: 8, minute: minute, second: 0, of: day(offset)) else { continue }
                checkIn.updatedAt = time
                checkIn.tz = TimeZone.current.secondsFromGMT(for: time)
                data.checkIns[AppData.key(UITestSupport.id(1), key)] = checkIn
            }
            if DesignScreen.requested == .smartEditor, let index = data.habits.firstIndex(where: { $0.id == UITestSupport.id(1) }) {
                data.habits[index].smartTime = true
            }
        }

        // 1.6, KAN-105: питомец уже был котиком, потом стал лисёнком со своим именем.
        let requested = DesignScreen.requested
        if [.petSwitched, .petNaming, .petSpecies].contains(requested) {
            data.wallet.ownedPets = ["bunny", "fox"]
            pet.names = ["cat": pet.name, "fox": ru ? "Рыжик" : "Ginger"]
            if requested == .petNaming {
                // Только что выбран зайчик, его ещё не называли: имя по виду, шит спрашивает своё.
                pet.species = "bunny"
                pet.name = Pets.defaultName(Pets.species("bunny"))
            } else {
                pet.species = "fox"
                pet.name = pet.names["fox"] ?? ""
            }
            data.wallet.pet = pet
        }
    }

    /// Шит редактора для существующей привычки.
    struct Editor: View {
        @Environment(HabitStore.self) private var store
        let id: UUID
        var body: some View {
            if let habit = store.habit(id) { HabitEditorView(habit: habit) }
        }
    }

    /// Редактор привычки, связанной с Apple Health («Пройти 10 000 шагов»), сразу на разделе Здоровья.
    struct HealthEditor: View {
        @Environment(HabitStore.self) private var store
        var body: some View {
            if let habit = store.data.activeHabits.first(where: { $0.health != nil }) {
                HabitEditorView(habit: habit).scrollingToHealth()
            }
        }
    }

    /// Редактор привычки сразу на разделе напоминания (умное время).
    struct ReminderEditor: View {
        @Environment(HabitStore.self) private var store
        let id: UUID
        var body: some View {
            if let habit = store.habit(id) { HabitEditorView(habit: habit).scrollingToReminder() }
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

    struct RecapScreen: View {
        @Environment(HabitStore.self) private var store
        var body: some View {
            RecapView(recap: Recap.lastWeek(in: store.data))
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
