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
        let items = habits.filter { $0.groupID == group.id }
        guard !items.isEmpty else { continue }
        items.forEach { used.insert($0.id) }
        result.append(HabitSection(id: group.id.uuidString, title: group.name, habits: items))
    }
    let rest = habits.filter { !used.contains($0.id) }
    if !rest.isEmpty {
        result.append(HabitSection(id: "ungrouped", title: "Без группы", habits: rest))
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
            .navigationTitle(isToday ? "Сегодня" : RuFormat.relativeDay(selectedDay))
            .toolbar {
                if !isToday {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Сегодня") {
                            withAnimation(.snappy) {
                                selectedDay = calendar.startOfDay(for: Date())
                            }
                        }
                    }
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
                    .navigationTransition(.zoom(sourceID: id, in: zoom))
            }
            .sheet(isPresented: $showingNewHabit) {
                HabitEditorView(habit: nil)
            }
            .sheet(item: $editingHabit) { habit in
                HabitEditorView(habit: habit)
            }
            .sheet(item: $noteTarget) { target in
                NoteEditorView(target: target)
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
                Text("История отметок тоже будет удалена.")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let habits = store.data.habits(on: selectedDay)
        if habits.isEmpty {
            if store.data.activeHabits.isEmpty {
                EmptyStateView(
                    systemImage: "sparkles",
                    title: "Начнём с первой привычки",
                    message: "Добавь привычку, выбери дни и время, и я напомню о ней.",
                    buttonTitle: "Добавить привычку",
                    action: { showingNewHabit = true }
                )
            } else {
                EmptyStateView(
                    systemImage: "sun.max.fill",
                    title: "Свободный день",
                    message: "На этот день привычек не запланировано."
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
        if progress.total == 0 { return "Свободный день" }
        if allDone { return "Всё выполнено!" }
        return "\(progress.done) из \(progress.total)"
    }

    private var subtitle: String {
        if progress.total == 0 { return "Можно отдохнуть" }
        if allDone { return "Отличная работа, так держать" }
        if isFuture { return "Запланировано " + RuPlural.habits(progress.total) }
        let left = progress.total - progress.done
        return "Осталось " + RuPlural.habits(left)
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
            .accessibilityLabel(isDone ? "Снять отметку" : "Отметить выполненной")
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
                    Label(isDone ? "Снять отметку" : "Выполнено", systemImage: isDone ? "arrow.uturn.backward" : "checkmark.circle")
                }
                Button(action: onSkip) {
                    Label(status == .skipped ? "Отменить пропуск" : "Пропустить", systemImage: "forward")
                }
                Button(action: onNote) {
                    Label(hasNote ? "Изменить заметку" : "Добавить заметку", systemImage: "note.text")
                }
                Divider()
            }
            Button(action: onEdit) {
                Label("Изменить привычку", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Удалить", systemImage: "trash")
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
                    Text("Пропущено")
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
