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
    case habitDetail, notifications, todayScreen, groups, backup
    // Шиты
    case catalog, editorNew, editorEdit, editorTemplate, iconPicker
    case profile, sparks, pet, paywall, feedback, note
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
        case .habitDetail, .notifications, .todayScreen, .groups, .backup: .push
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
        case .notifications: NotificationSettingsView()
        case .todayScreen: TodayScreenSettingsView()
        case .groups: GroupsView()
        case .backup: BackupSettingsView()
        case .catalog: HabitCatalogView()
        case .editorNew: HabitEditorView(habit: nil)
        case .editorEdit: DesignGallery.Editor(id: UITestSupport.id(1))
        case .editorTemplate: DesignGallery.TemplateEditor()
        case .iconPicker: DesignGallery.IconPicker()
        case .profile: ProfileView()
        case .sparks: SparksView()
        case .pet: PetView()
        case .paywall: PaywallView()
        case .feedback: FeedbackView()
        case .note: NoteEditorView(target: NoteTarget(habitID: UITestSupport.id(1), day: DayKey.make(Date())))
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
        let family = HabitGroup(id: UITestSupport.id(101), name: ru ? "Вечер" : "Evening", sortOrder: 1)
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

        // Питомец.
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
