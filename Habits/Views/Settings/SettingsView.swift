import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var pendingCount = 0

    private var repeatBinding: Binding<Int> {
        Binding(
            get: { store.data.settings.repeatCount },
            set: { store.setRepeatCount($0) }
        )
    }

    private var repeatDescription: String {
        let n = store.data.settings.repeatCount
        if n == 0 { return "Без повторов" }
        let minutes = n * store.data.settings.repeatIntervalMinutes
        let hours = minutes / 60
        let rest = minutes % 60
        var duration = ""
        if hours > 0 { duration += "\(hours) ч" }
        if rest > 0 { duration += (duration.isEmpty ? "" : " ") + "\(rest) мин" }
        return RuPlural.times(n) + ", в течение " + duration
    }

    private var statusText: String {
        switch authorization {
        case .authorized, .provisional, .ephemeral: return "Включены"
        case .denied: return "Выключены"
        case .notDetermined: return "Не настроены"
        @unknown default: return "Неизвестно"
        }
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        Text(statusText)
                    } label: {
                        Label("Уведомления", systemImage: "bell.badge.fill")
                    }
                    if authorization == .notDetermined {
                        Button("Разрешить уведомления") {
                            Task {
                                await NotificationPlanner.requestAuthorization()
                                await refresh()
                                await store.reschedule()
                            }
                        }
                    } else if authorization == .denied {
                        Button("Открыть настройки iOS") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }
                } footer: {
                    if authorization == .denied {
                        Text("Уведомления выключены в настройках iOS, поэтому напоминания не придут.")
                    }
                }

                Section {
                    Stepper(value: repeatBinding, in: 0...16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Повторы напоминания")
                            Text(repeatDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Если не отметить")
                } footer: {
                    Text("Пока привычка не отмечена, напоминание повторяется каждые \(store.data.settings.repeatIntervalMinutes) минут. Кнопки \"Готово\" и \"Пропустить\" в уведомлении останавливают повторы на этот день.")
                }

                Section("Организация") {
                    NavigationLink {
                        GroupsView()
                    } label: {
                        LabeledContent {
                            Text("\(store.data.groups.count)")
                        } label: {
                            Label("Группы", systemImage: "folder.fill")
                        }
                    }
                }

                Section {
                    LabeledContent("Запланировано уведомлений", value: "\(pendingCount)")
                    LabeledContent("Версия", value: version)
                } footer: {
                    Text("Все данные хранятся только на этом iPhone.")
                }
            }
            .navigationTitle("Настройки")
            .task { await refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await refresh() }
                }
            }
            .onChange(of: store.data.settings.repeatCount) { _, _ in
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    await refresh()
                }
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
                Text("Группы помогают разложить привычки по темам: утро, здоровье, работа.")
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
        .navigationTitle("Группы")
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
        .alert("Новая группа", isPresented: $showingNew) {
            TextField("Название", text: $newName)
            Button("Отмена", role: .cancel) {}
            Button("Создать") { store.addGroup(name: newName) }
        }
        .alert(
            "Переименовать",
            isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            ),
            presenting: renaming
        ) { group in
            TextField("Название", text: $renameText)
            Button("Отмена", role: .cancel) {}
            Button("Сохранить") { store.renameGroup(group.id, to: renameText) }
        }
    }
}
