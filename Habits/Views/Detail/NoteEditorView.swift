import SwiftUI

struct NoteEditorView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let target: NoteTarget

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if let habit = store.habit(target.habitID) {
                    HStack(spacing: 12) {
                        HabitIconView(icon: habit.icon, color: Palette.color(habit.colorIndex), size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(habit.name)
                                .font(.headline)
                            Text(DayKey.date(target.day).map { Fmt.relativeDay($0) } ?? target.day)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                TextEditor(text: $text)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 160)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.fill.tertiary))
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(AppBackground())
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.setNote(text, for: target.habitID, dayKey: target.day)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                text = store.data.note(target.habitID, day: target.day)
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
