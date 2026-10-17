import SwiftUI
import UIKit

struct HabitSection: Identifiable {
    let id: String
    let title: String
    let habits: [Habit]
}

/// Разбивает привычки по группам в порядке групп, без группы в конце.
func makeSections(_ habits: [Habit], data: AppData) -> [HabitSection] {
    var result: [HabitSection] = []
    var used = Set<UUID>()
    for group in data.sortedGroups {
        let items = habits.filter { $0.groupID == group.id }.sortedForDisplay()
        guard !items.isEmpty else { continue }
        items.forEach { used.insert($0.id) }
        result.append(HabitSection(id: group.id.uuidString, title: group.name, habits: items))
    }
    let rest = habits.filter { !used.contains($0.id) }.sortedForDisplay()
    if !rest.isEmpty {
        result.append(HabitSection(id: "ungrouped", title: String(localized: "No group"), habits: rest))
    }
    return result
}

struct TodayView: View {
    @Environment(HabitStore.self) private var store
    @State private var selectedDay: Date = Calendar.app.startOfDay(for: Date())
    @State private var showingNewHabit = false
    @State private var editingHabit: Habit?
    @State private var noteTarget: NoteTarget?
    @State private var habitToDelete: Habit?
    @State private var anchorToday: Date = Calendar.app.startOfDay(for: Date())
    @State private var showingOrder = false
    @State private var showingPaywall = false
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var zoom

    private var calendar: Calendar { .app }
    private var isToday: Bool { calendar.isDateInToday(selectedDay) }
    private var isFuture: Bool { selectedDay > calendar.startOfDay(for: Date()) }
    private var dayKey: String { DayKey.make(selectedDay) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WeekStrip(selected: $selectedDay)
                        .padding(.horizontal, -16)

                    let progress = Stats.day(selectedDay, in: store.data)
                    DayProgressCard(progress: progress, isFuture: isFuture)

                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .onChange(of: scenePhase) { _, phase in
                // Если приложение висело в памяти после полуночи, переключаемся на новый день.
                guard phase == .active else { return }
                let today = calendar.startOfDay(for: Date())
                if today != anchorToday {
                    if calendar.isDate(selectedDay, inSameDayAs: anchorToday) {
                        selectedDay = today
                    }
                    anchorToday = today
                }
            }
            .navigationTitle(isToday ? String(localized: "Today") : Fmt.relativeDay(selectedDay))
            .toolbar {
                if !isToday {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Today") {
                            withAnimation(.snappy) {
                                selectedDay = calendar.startOfDay(for: Date())
                            }
                        }
                    }
                }
                if store.data.activeHabits.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingOrder = true
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .accessibilityLabel("Habit order")
                    }
                }
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
                    .navigationTransition(.zoom(sourceID: id, in: zoom))
            }
            .sheet(isPresented: $showingNewHabit) {
                HabitEditorView(habit: nil)
            }
            .sheet(isPresented: $showingOrder) {
                HabitOrderView()
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(item: $editingHabit) { habit in
                HabitEditorView(habit: habit)
            }
            .sheet(item: $noteTarget) { target in
                NoteEditorView(target: target)
            }
            .confirmationDialog(
                "Delete habit?",
                isPresented: Binding(
                    get: { habitToDelete != nil },
                    set: { if !$0 { habitToDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: habitToDelete
            ) { habit in
                Button("Delete", role: .destructive) {
                    withAnimation { store.deleteHabit(habit.id) }
                }
            } message: { _ in
                Text("Its check-in history will be deleted too.")
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

    @ViewBuilder
    private var content: some View {
        let habits = store.data.habits(on: selectedDay)
        if habits.isEmpty {
            if store.data.activeHabits.isEmpty {
                EmptyStateView(
                    systemImage: "sparkles",
                    title: "Let's start with your first habit",
                    message: "Add a habit, pick days and a time, and I'll remind you.",
                    buttonTitle: "Add habit",
                    action: addHabit
                )
            } else {
                EmptyStateView(
                    systemImage: "sun.max.fill",
                    title: "Free day",
                    message: "No habits are planned for this day."
                )
            }
        } else {
            let sections = makeSections(habits, data: store.data)
            let showHeaders = sections.count > 1 || sections.first?.id != "ungrouped"
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    if showHeaders {
                        Text(section.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.leading, 8)
                            .padding(.top, 4)
                    }
                    ForEach(section.habits) { habit in
                        card(for: habit)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.95).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
            }
        }
    }

    private func card(for habit: Habit) -> some View {
        let status = store.data.status(habit.id, day: dayKey)
        let hasNote = !store.data.note(habit.id, day: dayKey).isEmpty
        let streak = Stats.habit(habit, in: store.data).currentStreak
        return HabitCard(
            habit: habit,
            status: status,
            hasNote: hasNote,
            streak: streak,
            canToggle: !isFuture,
            zoom: zoom,
            onToggle: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    store.toggleDone(habit.id, on: selectedDay)
                }
            },
            onSkip: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    store.setStatus(status == .skipped ? nil : .skipped, for: habit.id, on: selectedDay)
                }
            },
            onNote: { noteTarget = NoteTarget(habitID: habit.id, day: dayKey) },
            onEdit: { editingHabit = habit },
            onDelete: { habitToDelete = habit }
        )
    }
}

// MARK: - Карточка прогресса дня

struct DayProgressCard: View {
    let progress: DayProgress
    let isFuture: Bool

    private var allDone: Bool { progress.total > 0 && progress.done == progress.total }

    private var headline: String {
        if progress.total == 0 { return String(localized: "Free day") }
        if allDone { return String(localized: "All done!") }
        return String(localized: "\(progress.done) of \(progress.total)")
    }

    private var subtitle: String {
        if progress.total == 0 { return String(localized: "Time to rest") }
        if allDone { return String(localized: "Great job, keep it up") }
        if isFuture { return Fmt.habitsPlanned(progress.total) }
        let left = progress.total - progress.done
        return Fmt.habitsLeft(left)
    }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                ProgressRing(progress: progress.fraction, lineWidth: 10, color: .accentColor)
                if allDone {
                    Image(systemName: "checkmark")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(Color.accentColor)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("\(Int((progress.fraction * 100).rounded()))%")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.title3.weight(.bold))
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 18, cornerRadius: 26)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
        .sensoryFeedback(.success, trigger: allDone) { _, new in new }
    }
}

// MARK: - Карточка привычки

struct HabitCard: View {
    let habit: Habit
    let status: CheckStatus?
    let hasNote: Bool
    let streak: Int
    let canToggle: Bool
    let zoom: Namespace.ID
    var onToggle: () -> Void
    var onSkip: () -> Void
    var onNote: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    private var color: Color { Palette.color(habit.colorIndex) }
    private var isDone: Bool { status == .done }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: habit.id) {
                HStack(spacing: 14) {
                    HabitIconView(icon: habit.icon, color: color, size: 46)
                        .matchedTransitionSource(id: habit.id, in: zoom)
                        .saturation(status == .skipped ? 0.2 : 1)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(habit.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        details
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())

            Button(action: onToggle) {
                CheckMark(status: status, color: color, size: 34)
                    .symbolEffect(.bounce, value: isDone)
            }
            .buttonStyle(PressableStyle(scale: 0.82))
            .disabled(!canToggle)
            .opacity(canToggle ? 1 : 0.35)
            .sensoryFeedback(trigger: status) { _, new in
                new == .done ? .success : .selection
            }
            .accessibilityLabel(isDone ? String(localized: "Uncheck") : String(localized: "Mark as done"))
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(color.opacity(isDone ? 0.14 : 0))
                }
        }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contextMenu {
            if canToggle {
                Button(action: onToggle) {
                    Label(isDone ? String(localized: "Uncheck") : String(localized: "Mark as done"), systemImage: isDone ? "arrow.uturn.backward" : "checkmark.circle")
                }
                Button(action: onSkip) {
                    Label(status == .skipped ? String(localized: "Undo skip") : String(localized: "Skip"), systemImage: "forward")
                }
                Button(action: onNote) {
                    Label(hasNote ? String(localized: "Edit note") : String(localized: "Add note"), systemImage: "note.text")
                }
                Divider()
            }
            Button(action: onEdit) {
                Label("Edit habit", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: status)
    }

    @ViewBuilder
    private var details: some View {
        let hasAny = habit.reminder != nil || streak > 0 || hasNote || status == .skipped
        if hasAny {
            HStack(spacing: 10) {
                if status == .skipped {
                    Text("Skipped")
                }
                if let reminder = habit.reminder {
                    Label(reminder.text, systemImage: "bell.fill")
                }
                if streak > 0 {
                    Label("\(streak)", systemImage: "flame.fill")
                        .foregroundStyle(Color.orange)
                }
                if hasNote {
                    Image(systemName: "note.text")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .labelStyle(CompactLabelStyle())
        }
    }
}
