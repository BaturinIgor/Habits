import Combine
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

/// Потянуть список вниз: сразу забрать изменения родных из iCloud и данные Apple Health.
/// Только если есть семейные группы или привычки с Apple Health, иначе тянуть нечего.
private struct FamilyRefresh: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.refreshable {
                await FamilySync.shared.syncAll()
                await HealthSync.shared.sync()
            }
        } else {
            content
        }
    }
}

struct TodayView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDay: Date = Calendar.app.startOfDay(for: Date())
    @State private var anchorToday: Date = Calendar.app.startOfDay(for: Date())
    @State private var path: [UUID] = []
    @State private var groupFilter: UUID?
    @State private var showingCatalog = false
    @State private var wordsHabit: Habit?
    @State private var timerHabit: Habit?
    @State private var shownRecap: Recap?
    /// Неделя, месяц и год, итоги которых уже закрыли на «Сегодня».
    @AppStorage("weeklyRecapDismissed") private var recapDismissed = ""
    @AppStorage("monthlyRecapDismissed") private var monthRecapDismissed = ""
    @AppStorage("yearlyRecapDismissed") private var yearRecapDismissed = ""
    @State private var showingPaywall = false
    @State private var editingHabit: Habit?
    @State private var templateHabit: Habit?
    @State private var noteTarget: NoteTarget?
    @State private var habitToDelete: Habit?
    @State private var showingProfile = false
    @State private var showingSparks = false
    @State private var showingPet = false
    @State private var showingMoodJournal = false
    @State private var moodDay: MoodDay?
    @Namespace private var zoom

    private var calendar: Calendar { .app }
    private var isToday: Bool { calendar.isDateInToday(selectedDay) }
    private var isFuture: Bool { selectedDay > calendar.startOfDay(for: Date()) }
    private var dayKey: String { DayKey.make(selectedDay) }

    /// Привычки, которые человек бросает: счётчики дней показываем только на сегодня.
    private var quitHabits: [Habit] {
        guard isToday else { return [] }
        let all = store.data.activeHabits.filter(\.isQuit)
        guard let groupFilter, store.data.group(groupFilter) != nil else { return all }
        return all.filter { $0.groupID == groupFilter }
    }

    /// Первая привычка, чью вчерашнюю серию можно вернуть за искры.
    /// Итоги прошлого периода в первые три дня нового, пока их не закрыли:
    /// в начале года итоги года, в начале месяца итоги месяца, иначе в начале недели итоги недели.
    private var periodRecap: Recap? {
        let calendar = Calendar.app
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let dayOfMonth = calendar.component(.day, from: today)
        if dayOfMonth <= 3 {
            let isJanuary = calendar.component(.month, from: today) == 1
            let period: Recap.Period = isJanuary ? .year : .month
            let dismissed = isJanuary ? yearRecapDismissed : monthRecapDismissed
            // Ключ известен заранее, поэтому закрытые итоги даже не считаем.
            let startKey = isJanuary
                ? DayKey.make(calendar.date(byAdding: .year, value: -1, to: calendar.dateInterval(of: .year, for: today)?.start ?? today) ?? today, calendar: calendar)
                : DayKey.make(Recap.lastMonthStart(now: now, calendar: calendar), calendar: calendar)
            if startKey != dismissed {
                let recap = Recap.current(period, in: store.data, now: now, calendar: calendar)
                if recap.hasData, recap.key == startKey { return recap }
            }
        }
        let weekStart = Stats.startOfWeek(now, calendar: calendar)
        let daysIn = calendar.dateComponents([.day], from: weekStart, to: today).day ?? 0
        guard daysIn < 3, DayKey.make(Recap.lastWeekStart(now: now, calendar: calendar), calendar: calendar) != recapDismissed else { return nil }
        let recap = Recap.lastWeek(in: store.data, now: now, calendar: calendar)
        return recap.hasData ? recap : nil
    }

    private func dismissRecap(_ recap: Recap) {
        switch recap.period {
        case .week: recapDismissed = recap.key
        case .month: monthRecapDismissed = recap.key
        case .year: yearRecapDismissed = recap.key
        }
    }

    private var streakRepair: (Habit, (day: String, streak: Int))? {
        for habit in store.data.trackedHabits {
            if let repair = store.streakRepair(for: habit) { return (habit, repair) }
        }
        return nil
    }

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

                if store.data.wallet.pet != nil && isToday {
                    PetCard { showingPet = true }
                        .plainRow(top: 4, bottom: 6)
                }

                if !store.data.groups.isEmpty {
                    GroupFilterBar(selection: $groupFilter)
                        .plainRow(top: 4, bottom: 4, horizontal: 0)
                }

                if !store.data.settings.gestureHintShown && !visibleHabits.isEmpty && !isFuture {
                    GestureHint {
                        withAnimation { store.updateSettings { $0.gestureHintShown = true } }
                    }
                    .plainRow(top: 2, bottom: 2)
                }

                if isToday, let recap = periodRecap {
                    RecapBanner(recap: recap) {
                        shownRecap = recap
                    } onClose: {
                        withAnimation { dismissRecap(recap) }
                    }
                    .plainRow(top: 4, bottom: 6)
                }

                if isToday, let item = streakRepair {
                    StreakRepairCard(habit: item.0, repair: item.1, showName: true)
                        .plainRow(top: 4, bottom: 6)
                }

                content

                if !isFuture && store.data.settings.moodCard && !store.data.habits.isEmpty {
                    MoodCard(dayKey: dayKey, isToday: isToday) {
                        showingMoodJournal = true
                    } edit: {
                        moodDay = MoodDay(key: dayKey)
                    }
                    .plainRow(top: 10, bottom: 6)
                }

                quitSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .modifier(FamilyRefresh(enabled: (FamilySync.isAvailable && store.data.groups.contains { $0.family != nil })
                                    || (HealthSync.isAvailable && store.data.isPro && store.data.activeHabits.contains { $0.health != nil })))
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { rollOverDay() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
                rollOverDay()
            }
            .navigationTitle(isToday ? String(localized: "Today") : Fmt.relativeDay(selectedDay))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingProfile = true
                    } label: {
                        AvatarView(reward: Rewards.avatar(store.data.settings.avatarID), size: 30)
                    }
                    .accessibilityLabel("Profile")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSparks = true
                    } label: {
                        SparkBadge(amount: store.economy.balance)
                    }
                    .accessibilityLabel("Sparks")
                }
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
                    .accessibilityIdentifier("today.add")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                HabitDetailView(habitID: id)
                    .zoomTransition(sourceID: id, in: zoom)
            }
            .sheet(isPresented: $showingCatalog) {
                HabitCatalogView()
            }
            .fullScreenCover(item: $wordsHabit) { habit in
                WordsSessionView(habitID: habit.id)
            }
            .sheet(item: $timerHabit) { habit in
                HabitTimerView(habit: habit)
            }
            .sheet(item: $shownRecap) { recap in
                RecapView(recap: recap)
            }
            .sheet(isPresented: $showingMoodJournal) {
                MoodJournalView()
            }
            .sheet(item: $moodDay) { day in
                MoodEntryEditor(dayKey: day.key)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(highlight: .unlimited)
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
            .sheet(isPresented: $showingSparks) {
                SparksView()
            }
            .sheet(isPresented: $showingPet) {
                PetView()
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

    /// После полуночи переключаемся на новый день, если был открыт "сегодня".
    private func rollOverDay() {
        let today = calendar.startOfDay(for: Date())
        guard today != anchorToday else { return }
        if calendar.isDate(selectedDay, inSameDayAs: anchorToday) {
            selectedDay = today
        }
        anchorToday = today
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
            showingCatalog = true
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
                } else if quitHabits.isEmpty {
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
                    // Каждая часть - отдельный ForEach со своим onMove: перетащить можно
                    // только внутри части, поэтому строка не "отпрыгивает" после отпускания.
                    ForEach(moveGroups(section.habits)) { group in
                        ForEach(group.habits) { habit in
                            row(for: habit)
                                .moveDisabled(!group.movable)
                        }
                        .onMove { source, destination in
                            guard group.movable else { return }
                            move(group.habits, from: source, to: destination)
                        }
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

    @ViewBuilder
    private var quitSection: some View {
        let habits = quitHabits
        if !habits.isEmpty {
            Section {
                ForEach(habits) { habit in
                    QuitCard(habit: habit, showMoney: store.data.isPro) { path.append(habit.id) }
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
                        }
                }
            } header: {
                Text("Quitting")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
        }
    }

    private struct MoveGroup: Identifiable {
        let id: String
        let habits: [Habit]
        let movable: Bool
    }

    /// Делит секцию (она уже в порядке показа) на подряд идущие части, внутри которых
    /// порядок задаётся вручную. Привычки с напоминанием в режиме "по времени" не двигаются,
    /// а при "отмеченные внизу" неотмеченные и отмеченные двигаются каждая в своей части.
    private func moveGroups(_ habits: [Habit]) -> [MoveGroup] {
        let settings = store.data.settings
        var groups: [MoveGroup] = []
        var current: [Habit] = []
        var currentKey: (zone: Bool, movable: Bool)?
        func flush() {
            guard let key = currentKey, !current.isEmpty else { return }
            groups.append(MoveGroup(id: "\(groups.count)-\(key.zone)-\(key.movable)", habits: current, movable: key.movable))
            current = []
        }
        for habit in habits {
            let zone = settings.doneToBottom && store.data.status(habit.id, day: dayKey) != nil
            let movable = !(settings.homeLayout != .partsOfDay && habit.reminder != nil)
            if let key = currentKey, key.zone == zone, key.movable == movable {
                current.append(habit)
            } else {
                flush()
                currentKey = (zone, movable)
                current = [habit]
            }
        }
        flush()
        return groups
    }

    private func move(_ habits: [Habit], from source: IndexSet, to destination: Int) {
        var ids = habits.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        store.applyManualOrder(ids)
    }

    /// Прогресс по Apple Health за сегодня: "6 240/10 000".
    private func healthText(for habit: Habit) -> String? {
        guard isToday, let link = habit.health, store.data.isPro, HealthSync.isAvailable,
              let value = HealthSync.shared.today[habit.id] else { return nil }
        return link.metric.format(value) + "/" + link.metric.format(link.goal)
    }

    /// Таймер на карточке: идёт (время до конца) или просто длительность.
    private func timerInfo(for habit: Habit, status: CheckStatus?) -> HabitCard.TimerInfo? {
        guard isToday, store.data.isPro, let minutes = habit.timerMinutes, status == nil else { return nil }
        if let running = HabitTimer.shared.running, running.habitID == habit.id {
            return .running(running.start...running.end)
        }
        return .idle(minutes)
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
            isMinimum: data.checkIn(habit.id, day: dayKey)?.isMinimum == true,
            chainName: habit.chainAfter.flatMap { id in data.habits.first { $0.id == id }?.name },
            healthText: healthText(for: habit),
            timer: timerInfo(for: habit, status: status),
            canToggle: canToggle,
            zoom: zoom,
            onOpen: { path.append(habit.id) },
            onToggle: {
                // Слова учатся только сегодня: касание открывает карточки, а отметка ставится после них.
                if habit.isWords && isToday && status == nil {
                    wordsHabit = habit
                    return
                }
                // Привычка с таймером: касание открывает таймер, отметка ставится, когда время выйдет.
                if isToday, data.isPro, habit.timerMinutes != nil,
                   status == nil || HabitTimer.shared.isRunning(habit.id) {
                    timerHabit = habit
                    return
                }
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
                if !isDone, let minimum = habit.minimumVersion, !minimum.isEmpty {
                    Button {
                        withAnimation { store.markMinimum(habit.id, on: selectedDay) }
                    } label: {
                        Label(String(localized: "Minimum"), systemImage: "tortoise.fill")
                    }
                    .tint(.mint)
                }
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

// MARK: - Подсказка про жесты

struct GestureHint: View {
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.draw.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            Text("Swipe a card right to check it off, left for more actions. Press and hold to reorder.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .card(padding: 14, cornerRadius: 20)
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
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxHeight: .infinity)
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
        // Только когда день закрыли сейчас, а не при переключении на уже выполненный день.
        .sensoryFeedback(.success, trigger: allDone) { old, new in celebrate && new && !old }
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
    enum TimerInfo: Equatable {
        case running(ClosedRange<Date>)
        case idle(Int)
    }

    let habit: Habit
    let status: CheckStatus?
    let hasNote: Bool
    let streak: Int
    let target: Int
    let count: Int
    let weekDone: Int?
    var isMinimum: Bool = false
    var chainName: String? = nil
    var healthText: String? = nil
    var timer: TimerInfo? = nil
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
                        .zoomSource(id: habit.id, in: zoom)
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
            .accessibilityIdentifier("habit.open.\(habit.id.uuidString)")

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
            .accessibilityIdentifier("habit.toggle.\(habit.id.uuidString)")
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
            if isMinimum && isDone {
                Label(String(localized: "Minimum"), systemImage: "tortoise.fill")
            }
            if let chainName, status == nil {
                Label(String(localized: "After: \(chainName)"), systemImage: "link")
            }
            if let reminder = habit.reminder {
                Label(reminder.text, systemImage: "bell.fill")
            }
            if target > 1 {
                Label(amountText, systemImage: "target")
            }
            if let healthText, let link = habit.health {
                Label(healthText, systemImage: link.metric.symbol)
            }
            switch timer {
            case .running(let range):
                Label {
                    Text(timerInterval: range, countsDown: true)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "timer")
                }
                .foregroundStyle(Palette.color(habit.colorIndex))
            case .idle(let minutes):
                Label(String(localized: "\(minutes) min"), systemImage: "timer")
            case nil:
                EmptyView()
            }
            if let perDay = habit.wordsPerDay, habit.isWords {
                Label(String(localized: "\(perDay) words"), systemImage: "character.book.closed.fill")
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
