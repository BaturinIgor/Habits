import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var pendingCount = 0
    @State private var showingPaywall = false

    private var proBinding: Binding<Bool> {
        Binding(get: { store.data.isPro }, set: { store.setPro($0) })
    }

    private var statusText: LocalizedStringKey {
        switch authorization {
        case .authorized, .provisional, .ephemeral: return "On"
        case .denied: return "Off"
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        Text(statusText)
                    } label: {
                        Label("Notifications", systemImage: "bell.badge.fill")
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
                } footer: {
                    if authorization == .denied {
                        Text("Notifications are turned off in iOS Settings, so reminders won't arrive.")
                    } else {
                        Text(repeatsFooter)
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
                                Text("Habits Pro").foregroundStyle(Color.primary)
                            } icon: {
                                Image(systemName: "crown.fill").foregroundStyle(.orange)
                            }
                        }
                    }
                    Toggle("Pro test mode", isOn: proBinding)
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
            .onChange(of: store.data.isPro) { _, _ in
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    await refresh()
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
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
