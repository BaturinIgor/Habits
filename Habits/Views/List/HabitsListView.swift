import SwiftUI

struct HabitsListView: View {
    @Environment(HabitStore.self) private var store
    @State private var showingNewHabit = false
    @State private var showArchive = false
    @State private var habitToDelete: Habit?
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            List {
                let active = store.data.activeHabits
                if active.isEmpty {
                    EmptyStateView(
                        systemImage: "square.stack.fill",
                        title: "No habits yet",
                        message: "Create your first one and it will appear here.",
                        buttonTitle: "Add habit",
                        action: addHabit
                    )
                    .listRowBackground(Color.clear)
                }

                ForEach(makeSections(active, data: store.data)) { section in
                    Section(section.title) {
                        ForEach(section.habits) { habit in
                            NavigationLink(value: habit.id) {
                                HabitListRow(habit: habit)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    habitToDelete = habit
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    withAnimation { store.setArchived(habit.id, true) }
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }

                let archived = store.data.archivedHabits
                if !archived.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showArchive.animation()) {
                            ForEach(archived) { habit in
                                NavigationLink(value: habit.id) {
                                    HabitListRow(habit: habit)
                                        .opacity(0.6)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        habitToDelete = habit
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        withAnimation {
                                            if !store.unarchive(habit.id) { showingPaywall = true }
                                        }
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.green)
                                }
                            }
                        } label: {
                            Label("Archive (\(archived.count))", systemImage: "archivebox.fill")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addHabit()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New habit")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                HabitDetailView(habitID: id)
            }
            .sheet(isPresented: $showingNewHabit) {
                HabitEditorView(habit: nil)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .alert(
                "Delete habit?",
                isPresented: Binding(
                    get: { habitToDelete != nil },
                    set: { if !$0 { habitToDelete = nil } }
                ),
                presenting: habitToDelete
            ) { habit in
                Button("Delete", role: .destructive) {
                    withAnimation { store.deleteHabit(habit.id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Its check-in history will be deleted too. To keep the history, archive the habit instead.")
            }
        }
    }

    /// Добавление привычки с учётом лимита бесплатной версии.
    private func addHabit() {
        if store.data.canAddHabit {
            showingNewHabit = true
        } else {
            showingPaywall = true
        }
    }
}

struct HabitListRow: View {
    let habit: Habit

    var body: some View {
        HStack(spacing: 12) {
            HabitIconView(icon: habit.icon, color: Palette.color(habit.colorIndex), size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(habit.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(habit.scheduleSummary)
                        .lineLimit(1)
                    if let reminder = habit.reminder {
                        Label(reminder.text, systemImage: "bell.fill")
                            .labelStyle(CompactLabelStyle())
                    }
                    if let until = habit.pausedUntil, until >= Calendar.app.startOfDay(for: Date()) {
                        Label(String(localized: "Paused until \(Fmt.dayMonth(until))"), systemImage: "pause.fill")
                            .labelStyle(CompactLabelStyle())
                    }
                    if habit.hasEnded() {
                        Text("Ended")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
