import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var pendingCount = 0
    @State private var showingPaywall = false
    @State private var showingImporter = false
    @State private var pendingImport: URL?
    @State private var importResult: Bool?
    @State private var showingRestartHint = false
    @AppStorage("appLanguage") private var appLanguage = "system"

    private static let languages: [(code: String, name: String)] = [
        ("en", "English"), ("ru", "Русский"), ("de", "Deutsch"), ("fr", "Français"), ("es", "Español"),
        ("zh-Hans", "简体中文"), ("ja", "日本語"), ("ko", "한국어"), ("hi", "हिन्दी"),
    ]

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { store.data.settings[keyPath: keyPath] },
                set: { value in store.updateSettings { $0[keyPath: keyPath] = value } })
    }

    private var summaryTime: Binding<Date> {
        Binding(get: { store.data.settings.summaryTime.dateToday },
                set: { date in store.updateSettings { $0.summaryTime = ReminderTime(date: date) } })
    }

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

    private var permissionText: LocalizedStringKey {
        switch authorization {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied: return "Off in iPhone Settings"
        case .notDetermined: return "Not set up"
        @unknown default: return "Unknown"
        }
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private var repeatsFooter: String {
        let standard = Fmt.repeats(RepeatRule.standard.count, every: RepeatRule.standard.interval)
        return String(localized: "Until a habit is checked off, its reminder repeats: \(standard). Done and Skip in the notification stop the repeats for that day.")
    }

    /// Файл с копией всех данных для экспорта.
    private var exportURL: URL {
        let stamp = DayKey.make(Date())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("habits-backup-\(stamp).json")
        try? store.exportData().write(to: url, options: .atomic)
        return url
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: binding(\.remindersEnabled)) {
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
                } header: {
                    Text("Notifications")
                } footer: {
                    Text(repeatsFooter)
                }

                Section {
                    Toggle(isOn: binding(\.summaryEnabled).animation()) {
                        Label("Evening summary", systemImage: "moon.stars.fill")
                    }
                    if store.data.settings.summaryEnabled {
                        DatePicker("Time", selection: summaryTime, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("One notification listing the habits not checked off yet.")
                }

                Section("Today screen") {
                    Picker("Order", selection: binding(\.homeLayout)) {
                        Text("Parts of day").tag(HomeLayout.partsOfDay)
                        Text("By time").tag(HomeLayout.byTime)
                    }
                    Toggle("Done habits at the bottom", isOn: binding(\.doneToBottom))
                }

                Section {
                    Picker("Language", selection: languageBinding) {
                        Text("System").tag("system")
                        ForEach(Self.languages, id: \.code) { language in
                            Text(verbatim: language.name).tag(language.code)
                        }
                    }
                }

                Section {
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
                    Toggle("Pro test mode", isOn: binding(\.proUnlocked))
                } footer: {
                    Text("There are no purchases yet: this switch turns Pro features on for testing.")
                }

                Section("Organization") {
                    NavigationLink {
                        GroupsView()
                    } label: {
                        LabeledContent {
                            Text("\(store.data.groups.count)")
                        } label: {
                            Label("Groups", systemImage: "folder.fill")
                        }
                    }
                }

                Section {
                    ShareLink(item: exportURL) {
                        Label("Export data", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import data", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Save a copy to Files or iCloud Drive. Importing replaces all current data.")
                }

                Section {
                    LabeledContent("Scheduled notifications", value: "\(pendingCount)")
                    LabeledContent("Version", value: version)
                } footer: {
                    Text("All data is stored only on this iPhone.")
                }
            }
            .navigationTitle("Settings")
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
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
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
            .alert("Restart the app", isPresented: $showingRestartHint) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The new language will apply after you close the app and open it again.")
            }
        }
    }

    private func refresh() async {
        authorization = await NotificationPlanner.authorizationStatus()
        pendingCount = await NotificationPlanner.pendingCount()
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
