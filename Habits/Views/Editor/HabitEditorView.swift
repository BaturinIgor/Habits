import SwiftUI

struct HabitEditorView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let original: Habit?
    @State private var draft: Habit
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var showingNewGroup = false
    @State private var newGroupName = ""
    @State private var confirmDelete = false
    @State private var frequency: Frequency
    @State private var customDays: Set<Int>
    @State private var customRepeat: Bool
    @State private var repeatCount: Int
    @State private var repeatInterval: Int
    @State private var showingPaywall = false
    @State private var timesPerWeek: Int
    @State private var partOfDay: PartOfDay
    @State private var hasTarget: Bool
    @State private var target: Int
    @State private var unit: String
    @State private var isPaused: Bool
    @State private var pausedUntil: Date
    @FocusState private var nameFocused: Bool

    private enum Frequency: Hashable {
        case daily
        case days
        case weekly
        case once
    }

    private let calendar = Calendar.app

    init(habit: Habit?) {
        self.init(original: habit, base: habit)
    }

    /// Новая привычка из шаблона.
    init(template: Habit) {
        self.init(original: nil, base: template)
    }

    private init(original: Habit?, base: Habit?) {
        self.original = original
        let base = base ?? Habit(
            icon: .symbol(SymbolCatalog.symbols.randomElement() ?? "star.fill"),
            colorIndex: Int.random(in: 0..<Palette.colors.count)
        )
        let start = Calendar.app.startOfDay(for: base.schedule.startDate)
        _draft = State(initialValue: base)
        _hasEndDate = State(initialValue: base.schedule.endDate != nil)
        _endDate = State(initialValue: base.schedule.endDate
                         ?? Calendar.app.date(byAdding: .day, value: 30, to: start) ?? start)
        _hasReminder = State(initialValue: base.reminder != nil)
        _reminderDate = State(initialValue: (base.reminder ?? ReminderTime(hour: 9, minute: 0)).dateToday)
        let everyDay = base.schedule.weekdays == Weekdays.all
        switch base.schedule.kind {
        case .once: _frequency = State(initialValue: .once)
        case .weekly: _frequency = State(initialValue: .weekly)
        case .repeating: _frequency = State(initialValue: everyDay ? .daily : .days)
        }
        // В режиме "По дням" выбор начинается с пустого: нажимаешь дни, когда привычка нужна.
        _customDays = State(initialValue: everyDay ? [] : base.schedule.weekdays)
        _customRepeat = State(initialValue: base.repeatCount != nil)
        _repeatCount = State(initialValue: base.repeatCount ?? RepeatRule.standard.count)
        _repeatInterval = State(initialValue: base.repeatInterval ?? RepeatRule.standard.interval)
        _timesPerWeek = State(initialValue: base.schedule.timesPerWeek)
        _partOfDay = State(initialValue: base.partOfDay ?? .anytime)
        _hasTarget = State(initialValue: (base.target ?? 0) > 1)
        _target = State(initialValue: max(2, base.target ?? 8))
        _unit = State(initialValue: base.unit ?? "")
        let today = Calendar.app.startOfDay(for: Date())
        let pauseActive = (base.pausedUntil.map { $0 >= today }) ?? false
        _isPaused = State(initialValue: pauseActive)
        _pausedUntil = State(initialValue: pauseActive ? (base.pausedUntil ?? today)
                             : (Calendar.app.date(byAdding: .day, value: 7, to: today) ?? today))
    }

    private var color: Color { Palette.color(draft.colorIndex) }

    private var canSave: Bool {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return false }
        if frequency == .days && customDays.isEmpty { return false }
        return true
    }

    private var effectiveRepeat: RepeatRule {
        store.data.isPro && customRepeat ? RepeatRule(count: repeatCount, interval: repeatInterval) : .standard
    }

    private var repeatFooter: String {
        let rule = effectiveRepeat
        if rule.count == 0 { return String(localized: "One notification at the chosen time.") }
        let repeats = Fmt.repeats(rule.count, every: rule.interval)
        return String(localized: "If not checked off: \(repeats). Done in the notification stops the repeats.")
    }

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                appearanceSection
                scheduleSection
                reminderSection
                goalSection
                groupSection
                pauseSection
                if original != nil {
                    dangerSection
                }
            }
            .navigationTitle(original == nil ? String(localized: "New habit") : String(localized: "Edit habit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .alert("New group", isPresented: $showingNewGroup) {
                TextField("Name", text: $newGroupName)
                Button("Cancel", role: .cancel) { newGroupName = "" }
                Button("Create") {
                    let group = store.addGroup(name: newGroupName)
                    draft.groupID = group.id
                    newGroupName = ""
                }
            }
            .alert("Delete habit?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    if let original {
                        store.deleteHabit(original.id)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its check-in history will be deleted too.")
            }
            .onAppear {
                if original == nil { nameFocused = true }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
    }

    // MARK: Секции

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                HabitIconView(icon: draft.icon, color: color, size: 58)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: draft.colorIndex)
                TextField("Habit name", text: $draft.name, axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1...3)
                    .focused($nameFocused)
                    .submitLabel(.done)
            }
            .padding(.vertical, 6)
            TextField("Description or motivation (optional)", text: $draft.details, axis: .vertical)
                .lineLimit(1...4)
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            ColorRow(selection: $draft.colorIndex)
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
            NavigationLink {
                IconPickerView(icon: $draft.icon, color: color)
            } label: {
                HStack {
                    Text("Icon")
                    Spacer()
                    HabitIconView(icon: draft.icon, color: color, size: 30)
                }
            }
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            Picker("How often", selection: $frequency.animation(.snappy)) {
                Text("Every day").tag(Frequency.daily)
                Text("Some days").tag(Frequency.days)
                Text("Times a week").tag(Frequency.weekly)
                Text("Once").tag(Frequency.once)
            }

            if frequency == .once {
                DatePicker("Date", selection: $draft.schedule.onceDate, displayedComponents: .date)
            } else {
                if frequency == .days {
                    WeekdayPicker(selection: $customDays)
                }
                if frequency == .weekly {
                    Stepper(value: $timesPerWeek, in: 1...6) {
                        LabeledContent("Times a week", value: "\(timesPerWeek)")
                    }
                }
                DatePicker("Start", selection: $draft.schedule.startDate, displayedComponents: .date)
                Toggle("End date", isOn: $hasEndDate.animation(.snappy))
                if hasEndDate {
                    DatePicker(
                        "End",
                        selection: $endDate,
                        in: calendar.startOfDay(for: draft.schedule.startDate)...,
                        displayedComponents: .date
                    )
                }
            }
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle(isOn: $hasReminder.animation(.snappy)) {
                Label("Reminder", systemImage: "bell.badge.fill")
            }
            if !hasReminder {
                Picker("Part of day", selection: $partOfDay) {
                    ForEach(PartOfDay.allCases) { part in
                        Text(part.title).tag(part)
                    }
                }
            }
            if hasReminder {
                DatePicker("Time", selection: $reminderDate, displayedComponents: .hourAndMinute)
                if store.data.isPro {
                    Toggle(isOn: $customRepeat.animation(.snappy)) {
                        HStack(spacing: 8) {
                            Text("Custom repeats")
                            ProBadge()
                        }
                    }
                    if customRepeat {
                        Stepper(value: $repeatCount, in: 0...10) {
                            LabeledContent("Repeats", value: "\(repeatCount)")
                        }
                        Picker("Interval", selection: $repeatInterval) {
                            ForEach(RepeatRule.intervals, id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                    }
                } else {
                    lockedRow("Custom repeats")
                }
            }
        } header: {
            Text("Notification")
        } footer: {
            if hasReminder {
                Text(repeatFooter)
            }
        }
    }

    private var goalSection: some View {
        Section {
            if store.data.isPro {
                Toggle(isOn: $hasTarget.animation(.snappy)) {
                    HStack(spacing: 8) {
                        Text("Daily goal")
                        ProBadge()
                    }
                }
                if hasTarget {
                    Stepper(value: $target, in: 2...100) {
                        LabeledContent("Goal", value: "\(target)")
                    }
                    TextField("Unit, for example glasses", text: $unit)
                }
            } else {
                lockedRow("Daily goal")
            }
        } footer: {
            Text("For example, 8 glasses of water. Each tap on the circle adds one.")
        }
    }

    private var pauseSection: some View {
        Section {
            if store.data.isPro {
                Toggle(isOn: $isPaused.animation(.snappy)) {
                    HStack(spacing: 8) {
                        Text("Pause")
                        ProBadge()
                    }
                }
                if isPaused {
                    DatePicker("Until", selection: $pausedUntil, in: calendar.startOfDay(for: Date())..., displayedComponents: .date)
                }
            } else {
                lockedRow("Pause")
            }
        } footer: {
            Text("During a pause the habit is hidden and sends no reminders, and your streak is kept.")
        }
    }

    private func lockedRow(_ title: LocalizedStringKey) -> some View {
        Button {
            showingPaywall = true
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .foregroundStyle(Color.primary)
                ProBadge()
                Spacer()
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var groupSection: some View {
        Section("Group") {
            Picker("Group", selection: $draft.groupID) {
                Text("No group").tag(UUID?.none)
                ForEach(store.data.sortedGroups) { group in
                    Text(group.name).tag(Optional(group.id))
                }
            }
            Button {
                showingNewGroup = true
            } label: {
                Label("New group", systemImage: "folder.badge.plus")
            }
        }
    }

    private var dangerSection: some View {
        Section {
            Button {
                if let original {
                    if original.isArchived {
                        guard store.unarchive(original.id) else {
                            showingPaywall = true
                            return
                        }
                    } else {
                        store.setArchived(original.id, true)
                    }
                }
                dismiss()
            } label: {
                Label(draft.isArchived ? String(localized: "Restore from archive") : String(localized: "Move to archive"), systemImage: "archivebox")
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete habit", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("An archived habit is hidden from the Today screen and sends no notifications, but its history is kept.")
        }
    }

    // MARK: Сохранение

    private func save() {
        var habit = draft
        switch frequency {
        case .daily:
            habit.schedule.kind = .repeating
            habit.schedule.weekdays = Weekdays.all
        case .days:
            habit.schedule.kind = .repeating
            habit.schedule.weekdays = customDays
        case .weekly:
            habit.schedule.kind = .weekly
            habit.schedule.weekdays = Weekdays.all
        case .once:
            habit.schedule.kind = .once
        }
        habit.schedule.timesPerWeek = timesPerWeek
        habit.partOfDay = partOfDay
        if store.data.isPro {
            let cleanUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
            habit.target = hasTarget ? target : nil
            habit.unit = hasTarget && !cleanUnit.isEmpty ? cleanUnit : nil
            if isPaused {
                let today = calendar.startOfDay(for: Date())
                let wasActive = draft.pausedUntil.map { $0 >= today } ?? false
                habit.pausedFrom = wasActive ? (draft.pausedFrom ?? today) : today
                habit.pausedUntil = calendar.startOfDay(for: pausedUntil)
            } else {
                habit.pausedFrom = nil
                habit.pausedUntil = nil
            }
        }
        habit.name = habit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        habit.details = habit.details.trimmingCharacters(in: .whitespacesAndNewlines)
        habit.schedule.startDate = calendar.startOfDay(for: habit.schedule.startDate)
        habit.schedule.onceDate = calendar.startOfDay(for: habit.schedule.onceDate)
        if habit.schedule.kind != .once && hasEndDate {
            habit.schedule.endDate = max(calendar.startOfDay(for: endDate), habit.schedule.startDate)
        } else {
            habit.schedule.endDate = nil
        }
        habit.reminder = hasReminder ? ReminderTime(date: reminderDate) : nil
        if store.data.isPro {
            habit.repeatCount = customRepeat ? repeatCount : nil
            habit.repeatInterval = customRepeat ? repeatInterval : nil
        }
        store.upsert(habit)
        if habit.reminder != nil {
            Task {
                await NotificationPlanner.requestAuthorizationIfNeeded()
                await store.reschedule()
            }
        }
        dismiss()
    }
}

// MARK: - Выбор дней недели

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    private var summary: String {
        if selection.isEmpty { return String(localized: "Tap the days when the habit should be done") }
        let days = Weekdays.ordered.filter { selection.contains($0) }.map(Weekdays.short).joined(separator: ", ")
        return String(localized: "Days: \(days)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Weekdays.ordered, id: \.self) { weekday in
                    let isOn = selection.contains(weekday)
                    Text(Weekdays.short(weekday))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            Circle()
                                .fill(isOn ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.fill.tertiary))
                        }
                        .contentShape(Circle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if isOn { selection.remove(weekday) } else { selection.insert(weekday) }
                            }
                        }
                        .sensoryFeedback(.selection, trigger: isOn)
                }
            }
            HStack(spacing: 8) {
                preset("Weekdays", Weekdays.workdays)
                preset("Weekends", Weekdays.weekend)
                Spacer(minLength: 0)
            }
            Text(summary)
                .font(.footnote)
                .foregroundStyle(selection.isEmpty ? Color.orange : Color.secondary)
                .contentTransition(.opacity)
        }
        .padding(.vertical, 4)
    }

    private func preset(_ title: LocalizedStringKey, _ days: Set<Int>) -> some View {
        let active = selection == days
        return Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule().fill(active ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(.fill.quaternary))
            }
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selection = days }
            }
    }
}

// MARK: - Выбор цвета

struct ColorRow: View {
    @Binding var selection: Int

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Palette.colors.indices, id: \.self) { index in
                    let isSelected = index == selection
                    Circle()
                        .fill(Palette.colors[index].gradient)
                        .frame(width: 34, height: 34)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(3)
                        .overlay {
                            Circle()
                                .strokeBorder(Palette.colors[index], lineWidth: isSelected ? 2.5 : 0)
                        }
                        .scaleEffect(isSelected ? 1.08 : 1)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { selection = index }
                        }
                        .sensoryFeedback(.selection, trigger: isSelected)
                }
            }
            .padding(.vertical, 4)
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollIndicators(.hidden)
    }
}
