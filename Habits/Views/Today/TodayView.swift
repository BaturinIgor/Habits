import SwiftUI
import UIKit

extension View {
    /// Строка списка без фона и разделителей, с отступами как у карточек.
    func plainRow(top: CGFloat = 5, bottom: CGFloat = 5, horizontal: CGFloat = 16) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: horizontal, bottom: bottom, trailing: horizontal))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

struct TodayView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDay: Date = Calendar.app.startOfDay(for: Date())
    @State private var anchorToday: Date = Calendar.app.startOfDay(for: Date())
    @State private var path: [UUID] = []
    @State private var groupFilter: UUID?
    @State private var showingNewHabit = false
    @State private var showingPaywall = false
    @State private var editingHabit: Habit?
    @State private var templateHabit: Habit?
    @State private var noteTarget: NoteTarget?
    @State private var habitToDelete: Habit?
    @Namespace private var zoom

    private var calendar: Calendar { .app }
    private var isToday: Bool { calendar.isDateInToday(selectedDay) }
    private var isFuture: Bool { selectedDay > calendar.startOfDay(for: Date()) }
    private var dayKey: String { DayKey.make(selectedDay) }

    private var visibleHabits: [Habit] {
        let all = store.data.habits(on: selectedDay)
        guard let groupFilter, store.data.group(groupFilter) != nil else { return all }
        return all.filter { $0.groupID == groupFilter }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                WeekStrip(selected: $selectedDay)
                    .plainRow(top: 4, bottom: 6, horizontal: 0)

                DayProgressCard(progress: progress, isFuture: isFuture, celebrate: isToday)
                    .plainRow(top: 6, bottom: 6)

                if !store.data.groups.isEmpty {
                    GroupFilterBar(selection: $groupFilter)
                        .plainRow(top: 4, bottom: 4, horizontal: 0)
                }

                content
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .sheet(item: $editingHabit) { habit in
                HabitEditorView(habit: habit)
            }
            .sheet(item: $templateHabit) { habit in
                HabitEditorView(template: habit)
            }
            .sheet(item: $noteTarget) { target in
                NoteEditorView(target: target)
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
                Text("Its check-in history will be deleted too.")
            }
        }
    }

    private var progress: DayProgress {
        let p = Stats.day(selectedDay, in: store.data)
        guard groupFilter != nil else { return p }
        let ids = Set(visibleHabits.map(\.id))
        var done = 0
        var total = 0
        for habit in store.data.habits(on: selectedDay) where ids.contains(habit.id) {
            let status = store.data.status(habit.id, day: dayKey)
            if habit.schedule.kind == .weekly && status != .done { continue }
            if status == .done { done += 1; total += 1 } else if status == nil { total += 1 }
        }
        return DayProgress(date: p.date, done: done, total: total)
    }

    /// Добавление привычки с учётом лимита бесплатной версии.
    private func addHabit(template: Habit? = nil) {
        guard store.data.canAddHabit else {
            showingPaywall = true
            return
        }
        if let template {
            templateHabit = template
        } else {
            showingNewHabit = true
        }
    }

    @ViewBuilder
    private var content: some View {
        let habits = visibleHabits
        if habits.isEmpty {
            Group {
                if store.data.activeHabits.isEmpty {
                    VStack(spacing: 4) {
                        EmptyStateView(
                            systemImage: "sparkles",
                            title: "Let's start with your first habit",
                            message: "Pick a template or create your own.",
                            buttonTitle: "Add habit",
                            action: { addHabit() }
                        )
                        TemplatesGrid { addHabit(template: $0) }
                    }
                } else {
                    EmptyStateView(
                        systemImage: "sun.max.fill",
                        title: "Free day",
                        message: "No habits are planned for this day."
                    )
                }
            }
            .plainRow()
        } else {
            let sections = todaySections(habits, data: store.data, day: dayKey)
            ForEach(sections) { section in
                Section {
                    ForEach(section.habits) { habit in
                        row(for: habit)
                            .moveDisabled(store.data.settings.homeLayout == .byTime && habit.reminder != nil)
                    }
                    .onMove { source, destination in
                        move(in: section.habits, from: source, to: destination)
                    }
                } header: {
                    if !section.title.isEmpty {
                        Text(section.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                }
            }
        }
    }

    private func move(in habits: [Habit], from source: IndexSet, to destination: Int) {
        var ids = habits.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        let movable = store.data.settings.homeLayout == .byTime
            ? ids.filter { id in habits.first { $0.id == id }?.reminder == nil }
            : ids
        store.applyManualOrder(movable)
    }

    private func row(for habit: Habit) -> some View {
        let data = store.data
        let status = data.status(habit.id, day: dayKey)
        let hasNote = !data.note(habit.id, day: dayKey).isEmpty
        let target = habit.dailyTarget(isPro: data.isPro)
        let count = data.count(of: habit, day: dayKey)
        let isDone = status == .done
        let canToggle = !isFuture
        let color = Palette.color(habit.colorIndex)
        return HabitCard(
            habit: habit,
            status: status,
            hasNote: hasNote,
            streak: Stats.habit(habit, in: data).currentStreak,
            target: target,
            count: count,
            weekDone: habit.schedule.kind == .weekly ? data.weekDoneCount(habit, weekOf: selectedDay) : nil,
            canToggle: canToggle,
            zoom: zoom,
            onOpen: { path.append(habit.id) },
            onToggle: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    store.toggleDone(habit.id, on: selectedDay)
                }
            }
        )
        .plainRow()
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                habitToDelete = habit
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
            Button {
                editingHabit = habit
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.gray)
            if canToggle {
                Button {
                    noteTarget = NoteTarget(habitID: habit.id, day: dayKey)
                } label: {
                    Label(hasNote ? String(localized: "Edit note") : String(localized: "Note"), systemImage: "note.text")
                }
                .tint(.blue)
                Button {
                    withAnimation { store.setStatus(status == .skipped ? nil : .skipped, for: habit.id, on: selectedDay) }
                } label: {
                    Label(status == .skipped ? String(localized: "Undo skip") : String(localized: "Skip"), systemImage: "forward.fill")
                }
                .tint(.orange)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if canToggle {
                Button {
                    withAnimation { store.setStatus(isDone ? nil : .done, for: habit.id, on: selectedDay) }
                } label: {
                    Label(isDone ? String(localized: "Uncheck") : String(localized: "Mark as done"),
                          systemImage: isDone ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(isDone ? .gray : color)
                if target > 1 && count > 0 && !isDone {
                    Button {
                        withAnimation { store.decrement(habit.id, on: selectedDay) }
                    } label: {
                        Label(String(localized: "Minus one"), systemImage: "minus")
                    }
                    .tint(.gray)
                }
            }
        }
    }
}

// MARK: - Фильтр по группам

struct GroupFilterBar: View {
    @Environment(HabitStore.self) private var store
    @Binding var selection: UUID?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(String(localized: "All"), isOn: selection == nil) { selection = nil }
                ForEach(store.data.sortedGroups) { group in
                    chip(group.name, isOn: selection == group.id) { selection = group.id }
                }
            }
            .padding(.vertical, 2)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(isOn
                                   ? AnyShapeStyle(Color.accentColor.gradient)
                                   : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)))
                }
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Шаблоны

enum HabitTemplates {
    static func all(isPro: Bool) -> [Habit] {
        [
            Habit(name: String(localized: "Drink water"), icon: .emoji("💧"), colorIndex: 5, reminder: nil,
                  partOfDay: .anytime, target: isPro ? 8 : nil, unit: isPro ? String(localized: "glasses") : nil),
            Habit(name: String(localized: "Workout"), icon: .emoji("💪"), colorIndex: 0,
                  schedule: HabitSchedule(kind: .weekly, timesPerWeek: 3), reminder: ReminderTime(hour: 19, minute: 0)),
            Habit(name: String(localized: "Read"), icon: .emoji("📚"), colorIndex: 7, reminder: ReminderTime(hour: 21, minute: 0)),
            Habit(name: String(localized: "Meditate"), icon: .emoji("🧘"), colorIndex: 4, reminder: ReminderTime(hour: 8, minute: 0)),
            Habit(name: String(localized: "Walk"), icon: .emoji("🚶"), colorIndex: 3, reminder: nil, partOfDay: .afternoon),
            Habit(name: String(localized: "Go to bed on time"), icon: .emoji("😴"), colorIndex: 8, reminder: ReminderTime(hour: 22, minute: 30)),
        ]
    }
}

struct TemplatesGrid: View {
    @Environment(HabitStore.self) private var store
    var onPick: (Habit) -> Void

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(HabitTemplates.all(isPro: store.data.isPro)) { habit in
                Button {
                    onPick(habit)
                } label: {
                    HStack(spacing: 10) {
                        HabitIconView(icon: habit.icon, color: Palette.color(habit.colorIndex), size: 34)
                        Text(habit.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground)))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

// MARK: - Карточка прогресса дня

struct DayProgressCard: View {
    let progress: DayProgress
    let isFuture: Bool
    var celebrate: Bool = false
    @State private var confetti = 0

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
        return Fmt.habitsLeft(progress.total - progress.done)
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
                    Text(verbatim: "\(Int((progress.fraction * 100).rounded()))%")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .frame(width: 72, height: 72)
            .overlay { ConfettiBurst(trigger: confetti) }

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
        .onChange(of: allDone) { old, new in
            if celebrate && new && !old { confetti += 1 }
        }
    }
}

/// Небольшой салют, когда все привычки дня выполнены.
struct ConfettiBurst: View {
    let trigger: Int

    private struct Piece: Identifiable {
        let id = UUID()
        let color: Color
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
        let spin: Double
    }

    @State private var pieces: [Piece] = []
    @State private var fired = false

    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(piece.color)
                    .frame(width: piece.size, height: piece.size * 0.6)
                    .rotationEffect(.degrees(fired ? piece.spin : 0))
                    .offset(x: fired ? cos(piece.angle) * piece.distance : 0,
                            y: fired ? sin(piece.angle) * piece.distance + 30 : 0)
                    .opacity(fired ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            pieces = (0..<40).map { _ in
                Piece(color: Palette.colors.randomElement() ?? .orange,
                      angle: .random(in: 0...(2 * .pi)),
                      distance: .random(in: 70...190),
                      size: .random(in: 6...10),
                      spin: .random(in: -360...360))
            }
            fired = false
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 1.2)) { fired = true }
            }
        }
    }
}

// MARK: - Карточка привычки

struct HabitCard: View {
    let habit: Habit
    let status: CheckStatus?
    let hasNote: Bool
    let streak: Int
    let target: Int
    let count: Int
    let weekDone: Int?
    let canToggle: Bool
    let zoom: Namespace.ID
    var onOpen: () -> Void
    var onToggle: () -> Void

    private var color: Color { Palette.color(habit.colorIndex) }
    private var isDone: Bool { status == .done }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
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
                CheckMark(
                    status: status,
                    color: color,
                    size: 34,
                    progress: target > 1 ? Double(count) / Double(target) : 0,
                    countText: target > 1 && count > 0 && !isDone ? "\(count)" : nil
                )
                .symbolEffect(.bounce, value: isDone)
            }
            .buttonStyle(PressableStyle(scale: 0.82))
            .disabled(!canToggle)
            .opacity(canToggle ? 1 : 0.35)
            .sensoryFeedback(trigger: count) { _, _ in isDone ? .success : .selection }
            .sensoryFeedback(trigger: status) { _, new in new == .done ? .success : .selection }
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
        .opacity(status == .skipped ? 0.75 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: status)
    }

    @ViewBuilder
    private var details: some View {
        HStack(spacing: 10) {
            if status == .skipped {
                Text("Skipped")
            }
            if let reminder = habit.reminder {
                Label(reminder.text, systemImage: "bell.fill")
            }
            if target > 1 {
                Label(amountText, systemImage: "drop.fill")
            }
            if let weekDone {
                Label(String(localized: "\(weekDone) of \(habit.schedule.timesPerWeek) this week"), systemImage: "calendar")
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
        .lineLimit(1)
    }

    private var amountText: String {
        let unit = (habit.unit ?? "").trimmingCharacters(in: .whitespaces)
        return unit.isEmpty ? "\(count)/\(target)" : "\(count)/\(target) \(unit)"
    }
}
