import WidgetKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// Привязка поля настроек к хранилищу: запись сохраняет и пересчитывает уведомления.
extension HabitStore {
    func settingBinding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { self.data.settings[keyPath: keyPath] },
                set: { value in self.updateSettings { $0[keyPath: keyPath] = value } })
    }
}

/// Главный экран настроек: короткий список, подробности на отдельных экранах.
struct SettingsView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var showingPaywall = false
    @State private var showingRestartHint = false
    @State private var showingProfile = false
    @State private var showingFeedback = false
    @AppStorage("appLanguage") private var appLanguage = "system"

    private static let languages: [(code: String, name: String)] = [
        ("en", "English"), ("ru", "Русский"), ("de", "Deutsch"), ("fr", "Français"), ("es", "Español"),
        ("zh-Hans", "简体中文"), ("ja", "日本語"), ("ko", "한국어"), ("hi", "हिन्दी"),
    ]

    private var languageBinding: Binding<String> {
        Binding(get: { appLanguage }, set: { code in
            appLanguage = code
            if code == "system" {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([code], forKey: "AppleLanguages")
            }
            showingRestartHint = true
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingProfile = true
                    } label: {
                        Label {
                            Text("Profile and achievements").foregroundStyle(Color.primary)
                        } icon: {
                            Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                        }
                    }
                    Button {
                        showingPaywall = true
                    } label: {
                        LabeledContent {
                            Text(store.data.isPro ? String(localized: "Active") : String(localized: "Free version"))
                        } label: {
                            Label {
                                Text("Habit Tracker Pro").foregroundStyle(Color.primary)
                            } icon: {
                                Image(systemName: "crown.fill").foregroundStyle(.orange)
                            }
                        }
                    }
                    #if SIDELOAD
                    Toggle("Pro test mode", isOn: store.settingBinding(\.proUnlocked))
                    #endif
                } footer: {
                    #if SIDELOAD
                    Text("There are no purchases yet: this switch turns Pro features on for testing.")
                    #endif
                }

                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        LabeledContent {
                            Text(store.data.settings.remindersEnabled ? String(localized: "On") : String(localized: "Off"))
                        } label: {
                            Label("Notifications", systemImage: "bell.badge.fill")
                        }
                    }
                    NavigationLink {
                        TodayScreenSettingsView()
                    } label: {
                        Label("Today screen", systemImage: "list.bullet.rectangle.fill")
                    }
                    NavigationLink {
                        GroupsView()
                    } label: {
                        LabeledContent {
                            Text("\(store.data.groups.count)")
                        } label: {
                            Label("Groups", systemImage: "folder.fill")
                        }
                    }
                    Picker(selection: languageBinding) {
                        Text("System").tag("system")
                        ForEach(Self.languages, id: \.code) { language in
                            Text(verbatim: language.name).tag(language.code)
                        }
                    } label: {
                        Label("Language", systemImage: "globe")
                    }
                    .pickerStyle(.navigationLink)
                }

                WidgetStatusSection()

                Section {
                    NavigationLink {
                        BackupSettingsView()
                    } label: {
                        Label("Backup", systemImage: "externaldrive.fill")
                    }
                }

                Section {
                    Button {
                        showingFeedback = true
                    } label: {
                        Label("Write to the developer", systemImage: "envelope.fill")
                    }
                    if let url = AppInfo.reviewURL {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Rate the app", systemImage: "star.fill")
                        }
                    }
                    Button {
                        store.updateSettings { $0.onboardingDone = false; $0.gestureHintShown = false }
                    } label: {
                        Label("Show introduction", systemImage: "questionmark.circle.fill")
                    }
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("Found a bug or have an idea? Every message is read.")
                }

                Section {
                    LabeledContent("Version", value: AppInfo.version)
                } footer: {
                    Text("All data is stored only on this iPhone.")
                }
            }
            .appBackground()
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
            .sheet(isPresented: $showingFeedback) {
                FeedbackView()
            }
            .alert("Restart the app", isPresented: $showingRestartHint) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The new language will apply after you close the app and open it again.")
            }
        }
    }
}

// MARK: - Виджет

/// Состояние виджета одной строкой. Подсказка видна только при проблеме.
private struct WidgetStatusSection: View {
    @State private var widgetBeat = WidgetHeartbeat.read()
    @State private var spins = 0

    private var available: Bool { AppGroup.resolvedIdentifier != nil }

    var body: some View {
        Section {
            HStack(spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(available ? LocalizedStringKey("Available") : LocalizedStringKey("Not available"))
                        HStack(spacing: 4) {
                            Text("Last widget update")
                            Text(verbatim: "·")
                            if let beat = widgetBeat {
                                Text(beat.date, format: .relative(presentation: .named))
                            } else {
                                Text("Never")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                } icon: {
                    Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(available ? Color.green : Color.red)
                }
                Spacer(minLength: 0)
                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(Double(spins) * 360))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Refresh widgets"))
            }
        } header: {
            Text("Widget")
        } footer: {
            if !available {
                Text("If shared data is not available, the widget can't see your habits. Reinstall the app through SideStore and keep its app extensions when asked.")
            }
        }
    }

    private func refresh() {
        WidgetCenter.shared.reloadAllTimelines()
        withAnimation(.easeInOut(duration: 0.6)) { spins += 1 }
        Task {
            try? await Task.sleep(for: .seconds(2))
            widgetBeat = WidgetHeartbeat.read()
        }
    }
}

// MARK: - Уведомления

struct NotificationSettingsView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var pendingCount = 0

    private var summaryTime: Binding<Date> {
        Binding(get: { store.data.settings.summaryTime.dateToday },
                set: { date in store.updateSettings { $0.summaryTime = ReminderTime(date: date) } })
    }

    private var permissionText: LocalizedStringKey {
        switch authorization {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied: return "Off in iPhone Settings"
        case .notDetermined: return "Not set up"
        @unknown default: return "Unknown"
        }
    }

    private var repeatsFooter: String {
        let standard = Fmt.repeats(RepeatRule.standard.count, every: RepeatRule.standard.interval)
        return String(localized: "Until a habit is checked off, its reminder repeats: \(standard). Done and Skip in the notification stop the repeats for that day.")
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: store.settingBinding(\.remindersEnabled)) {
                    Label("Reminders", systemImage: "bell.badge.fill")
                }
                LabeledContent("iPhone permission") {
                    Text(permissionText)
                }
                if authorization == .notDetermined {
                    Button("Allow notifications") {
                        Task {
                            await NotificationPlanner.requestAuthorization()
                            await refresh()
                            await store.reschedule()
                        }
                    }
                } else if authorization == .denied {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
                LabeledContent("Scheduled notifications", value: "\(pendingCount)")
            } footer: {
                Text(repeatsFooter)
            }

            Section {
                Toggle(isOn: store.settingBinding(\.summaryEnabled).animation()) {
                    Label("Evening summary", systemImage: "moon.stars.fill")
                }
                if store.data.settings.summaryEnabled {
                    DatePicker("Time", selection: summaryTime, displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("One notification listing the habits not checked off yet.")
            }

            Section {
                Toggle(isOn: store.settingBinding(\.badgeEnabled)) {
                    Label("Number on the app icon", systemImage: "app.badge.fill")
                }
            } footer: {
                Text("Shows how many reminders came since you last opened the app.")
            }
        }
        .appBackground()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refresh() }
            }
        }
        .onChange(of: store.data.settings) { _, _ in
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                await refresh()
            }
        }
    }

    private func refresh() async {
        authorization = await NotificationPlanner.authorizationStatus()
        pendingCount = await NotificationPlanner.pendingCount()
    }
}

// MARK: - Экран «Сегодня»

struct TodayScreenSettingsView: View {
    @Environment(HabitStore.self) private var store

    var body: some View {
        Form {
            Section {
                Picker("Order", selection: store.settingBinding(\.homeLayout)) {
                    Text("Parts of day").tag(HomeLayout.partsOfDay)
                    Text("By time").tag(HomeLayout.byTime)
                }
                Toggle("Done habits at the bottom", isOn: store.settingBinding(\.doneToBottom))
            }
        }
        .appBackground()
        .navigationTitle("Today screen")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Резервная копия

struct BackupSettingsView: View {
    @Environment(HabitStore.self) private var store
    @State private var showingImporter = false
    @State private var pendingImport: URL?
    @State private var importResult: Bool?

    @State private var exportURL: URL?

    /// Файл с копией всех данных пишется один раз при открытии экрана, а не на каждой перерисовке.
    private func prepareExport() {
        let stamp = DayKey.make(Date())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("habits-backup-\(stamp).json")
        exportURL = (try? store.exportData().write(to: url, options: .atomic)) != nil ? url : nil
    }

    var body: some View {
        Form {
            Section {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Export data", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Label("Export data", systemImage: "square.and.arrow.up")
                        .foregroundStyle(.secondary)
                }
                Button {
                    showingImporter = true
                } label: {
                    Label("Import data", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("Save a copy to Files or iCloud Drive. Importing replaces all current data.")
            }
        }
        .appBackground()
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prepareExport)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                pendingImport = url
            }
        }
        .alert(
            "Replace all data?",
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            presenting: pendingImport
        ) { url in
            Button("Import", role: .destructive) {
                importResult = store.importData(from: url)
                prepareExport()
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Current habits and history will be replaced with the data from the file.")
        }
        .alert(
            importResult == true ? String(localized: "Data imported") : String(localized: "Couldn't read the file"),
            isPresented: Binding(get: { importResult != nil }, set: { if !$0 { importResult = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }
}

// MARK: - Группы

struct GroupsView: View {
    @Environment(HabitStore.self) private var store
    @State private var showingNew = false
    @State private var newName = ""
    @State private var renaming: HabitGroup?
    @State private var renameText = ""

    var body: some View {
        List {
            if store.data.groups.isEmpty {
                Text("Groups help sort habits by topic: morning, health, work.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.data.sortedGroups) { group in
                let count = store.data.habits.filter { $0.groupID == group.id }.count
                Button {
                    renameText = group.name
                    renaming = group
                } label: {
                    LabeledContent {
                        Text("\(count)")
                    } label: {
                        Label(group.name, systemImage: "folder")
                            .foregroundStyle(Color.primary)
                    }
                }
            }
            .onDelete { offsets in
                let groups = store.data.sortedGroups
                for index in offsets {
                    store.deleteGroup(groups[index].id)
                }
            }
            .onMove { source, destination in
                store.moveGroups(from: source, to: destination)
            }
        }
        .appBackground()
        .navigationTitle("Groups")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newName = ""
                    showingNew = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .alert("New group", isPresented: $showingNew) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { store.addGroup(name: newName) }
        }
        .alert(
            "Rename",
            isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            ),
            presenting: renaming
        ) { group in
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { store.renameGroup(group.id, to: renameText) }
        }
    }
}
