import SwiftUI

struct HabitsListView: View {
    @Environment(HabitStore.self) private var store
    @State private var showingNewHabit = false
    @State private var showArchive = false
    @State private var habitToDelete: Habit?

    var body: some View {
        NavigationStack {
            List {
                let active = store.data.activeHabits
                if active.isEmpty {
                    EmptyStateView(
                        systemImage: "square.stack.fill",
                        title: "Привычек пока нет",
                        message: "Создай первую, и она появится здесь.",
                        buttonTitle: "Добавить привычку",
                        action: { showingNewHabit = true }
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
                                    Label("Удалить", systemImage: "trash")
                                }
                                Button {
                                    withAnimation { store.setArchived(habit.id, true) }
                                } label: {
                                    Label("В архив", systemImage: "archivebox")
                                }
                                .tint(.orange)
                            }
                        }
                        .onMove { source, destination in
                            store.reorder(section.habits.map(\.id), from: source, to: destination)
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
                                        Label("Удалить", systemImage: "trash")
                                    }
                                    Button {
                                        withAnimation { store.setArchived(habit.id, false) }
                                    } label: {
                                        Label("Вернуть", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.green)
                                }
                            }
                        } label: {
                            Label("Архив (\(archived.count))", systemImage: "archivebox.fill")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Привычки")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewHabit = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Новая привычка")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                HabitDetailView(habitID: id)
            }
            .sheet(isPresented: $showingNewHabit) {
                HabitEditorView(habit: nil)
            }
            .confirmationDialog(
                "Удалить привычку?",
                isPresented: Binding(
                    get: { habitToDelete != nil },
                    set: { if !$0 { habitToDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: habitToDelete
            ) { habit in
                Button("Удалить", role: .destructive) {
                    withAnimation { store.deleteHabit(habit.id) }
                }
            } message: { _ in
                Text("История отметок тоже будет удалена. Если хочешь сохранить историю, перемести привычку в архив.")
            }
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
                    if habit.hasEnded() {
                        Text("Завершена")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
