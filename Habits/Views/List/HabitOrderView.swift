import SwiftUI

/// Экран порядка привычек. Привычки с напоминанием стоят по времени и не двигаются,
/// остальные перетаскиваются за ручку справа.
struct HabitOrderView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let sections = makeSections(store.data.activeHabits, data: store.data)
                let showHeaders = sections.count > 1 || sections.first?.id != "ungrouped"
                ForEach(sections) { section in
                    Section {
                        ForEach(section.habits) { habit in
                            HabitOrderRow(habit: habit)
                                .moveDisabled(habit.reminder != nil)
                        }
                        .onMove { source, destination in
                            move(in: section.habits, from: source, to: destination)
                        }
                    } header: {
                        if showHeaders {
                            Text(section.title)
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .safeAreaInset(edge: .top) {
                Text("Habits with reminders are sorted by time. The rest come after them and can be dragged.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
            .navigationTitle("Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: store.data.habits.map(\.sortOrder))
    }

    private func move(in habits: [Habit], from source: IndexSet, to destination: Int) {
        var ids = habits.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        // Порядок задаётся только среди привычек без напоминания.
        let manual = ids.filter { id in habits.first { $0.id == id }?.reminder == nil }
        withAnimation(.snappy) {
            store.applyManualOrder(manual)
        }
    }
}

private struct HabitOrderRow: View {
    let habit: Habit

    var body: some View {
        HStack(spacing: 12) {
            HabitIconView(icon: habit.icon, color: Palette.color(habit.colorIndex), size: 34)
            Text(habit.name)
                .font(.body.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            if let reminder = habit.reminder {
                Label(reminder.text, systemImage: "bell.fill")
                    .labelStyle(CompactLabelStyle())
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}
