import SwiftUI

/// Отдельный экран сортировки. Порядок меняется в локальной копии и сохраняется
/// кнопкой "Готово", поэтому строка всегда остаётся ровно там, куда её перетащили.
struct ReorderView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private struct Block: Identifiable {
        let id: String
        let title: String
        var habits: [Habit]
        let movable: Bool
    }

    @State private var blocks: [Block] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach($blocks) { $block in
                    Section {
                        ForEach(block.habits) { habit in
                            HStack(spacing: 12) {
                                HabitIconView(icon: habit.icon, color: Palette.color(habit.colorIndex), size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(habit.name)
                                        .font(.body.weight(.medium))
                                        .lineLimit(1)
                                    if let reminder = habit.reminder {
                                        Text(reminder.text)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .moveDisabled(!block.movable)
                        }
                        .onMove { source, destination in
                            block.habits.move(fromOffsets: source, toOffset: destination)
                        }
                    } header: {
                        Text(block.title)
                    } footer: {
                        if !block.movable {
                            Text("Habits with a reminder are sorted by time automatically.")
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.setOrder(blocks.flatMap { $0.habits.map(\.id) })
                        dismiss()
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard blocks.isEmpty else { return }
        let habits = store.data.activeHabits.sorted(by: Habit.manualOrder)
        switch store.data.settings.homeLayout {
        case .partsOfDay:
            blocks = PartOfDay.allCases.compactMap { part in
                let items = habits.filter { $0.effectivePartOfDay == part }
                return items.isEmpty ? nil : Block(id: part.rawValue, title: part.title, habits: items, movable: true)
            }
        case .byTime:
            let timed = habits.filter { $0.reminder != nil }.sortedForDisplay()
            let free = habits.filter { $0.reminder == nil }
            blocks = [
                Block(id: "free", title: String(localized: "Without reminder"), habits: free, movable: true),
                Block(id: "timed", title: String(localized: "With reminder"), habits: timed, movable: false),
            ].filter { !$0.habits.isEmpty }
        }
    }
}
