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
    @FocusState private var nameFocused: Bool

    private let calendar = Calendar.app

    init(habit: Habit?) {
        original = habit
        let base = habit ?? Habit(
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
    }

    private var color: Color { Palette.color(draft.colorIndex) }

    private var canSave: Bool {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return false }
        if draft.schedule.kind == .repeating && draft.schedule.weekdays.isEmpty { return false }
        return true
    }

    private var repeatFooter: String {
        let n = store.data.settings.repeatCount
        if n == 0 { return "Одно уведомление в выбранное время." }
        let interval = store.data.settings.repeatIntervalMinutes
        return "Если не отметить, напомню ещё \(RuPlural.times(n)) каждые \(interval) минут. Кнопка \"Готово\" в уведомлении остановит повторы."
    }

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                appearanceSection
                scheduleSection
                reminderSection
                groupSection
                if original != nil {
                    dangerSection
                }
            }
            .navigationTitle(original == nil ? "Новая привычка" : "Изменить привычку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .alert("Новая группа", isPresented: $showingNewGroup) {
                TextField("Название", text: $newGroupName)
                Button("Отмена", role: .cancel) { newGroupName = "" }
                Button("Создать") {
                    let group = store.addGroup(name: newGroupName)
                    draft.groupID = group.id
                    newGroupName = ""
                }
            }
            .confirmationDialog("Удалить привычку?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if let original {
                        store.deleteHabit(original.id)
                    }
                    dismiss()
                }
            } message: {
                Text("История отметок тоже будет удалена.")
            }
            .onAppear {
                if original == nil { nameFocused = true }
            }
        }
    }

    // MARK: Секции

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                HabitIconView(icon: draft.icon, color: color, size: 58)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: draft.colorIndex)
                TextField("Название привычки", text: $draft.name, axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1...3)
                    .focused($nameFocused)
                    .submitLabel(.done)
            }
            .padding(.vertical, 6)
            TextField("Описание или мотивация (необязательно)", text: $draft.details, axis: .vertical)
                .lineLimit(1...4)
        }
    }

    private var appearanceSection: some View {
        Section("Оформление") {
            ColorRow(selection: $draft.colorIndex)
                .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
            NavigationLink {
                IconPickerView(icon: $draft.icon, color: color)
            } label: {
                HStack {
                    Text("Иконка")
                    Spacer()
                    HabitIconView(icon: draft.icon, color: color, size: 30)
                }
            }
        }
    }

    private var scheduleSection: some View {
        Section("Расписание") {
            Picker("Тип", selection: $draft.schedule.kind.animation(.snappy)) {
                Text("Регулярно").tag(HabitSchedule.Kind.repeating)
                Text("Один раз").tag(HabitSchedule.Kind.once)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            if draft.schedule.kind == .once {
                DatePicker("Дата", selection: $draft.schedule.onceDate, displayedComponents: .date)
            } else {
                WeekdayPicker(selection: $draft.schedule.weekdays)
                DatePicker("Начало", selection: $draft.schedule.startDate, displayedComponents: .date)
                Toggle("Дата окончания", isOn: $hasEndDate.animation(.snappy))
                if hasEndDate {
                    DatePicker(
                        "Окончание",
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
                Label("Напоминание", systemImage: "bell.badge.fill")
            }
            if hasReminder {
                DatePicker("Время", selection: $reminderDate, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Уведомление")
        } footer: {
            if hasReminder {
                Text(repeatFooter)
            }
        }
    }

    private var groupSection: some View {
        Section("Группа") {
            Picker("Группа", selection: $draft.groupID) {
                Text("Без группы").tag(UUID?.none)
                ForEach(store.data.sortedGroups) { group in
                    Text(group.name).tag(Optional(group.id))
                }
            }
            Button {
                showingNewGroup = true
            } label: {
                Label("Новая группа", systemImage: "folder.badge.plus")
            }
        }
    }

    private var dangerSection: some View {
        Section {
            Button {
                if let original {
                    store.setArchived(original.id, !original.isArchived)
                }
                dismiss()
            } label: {
                Label(draft.isArchived ? "Вернуть из архива" : "Переместить в архив", systemImage: "archivebox")
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Удалить привычку", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        } footer: {
            Text("Архивная привычка не показывается на главном экране и не присылает уведомления, но её история сохраняется.")
        }
    }

    // MARK: Сохранение

    private func save() {
        var habit = draft
        habit.name = habit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        habit.details = habit.details.trimmingCharacters(in: .whitespacesAndNewlines)
        habit.schedule.startDate = calendar.startOfDay(for: habit.schedule.startDate)
        habit.schedule.onceDate = calendar.startOfDay(for: habit.schedule.onceDate)
        if habit.schedule.kind == .repeating && hasEndDate {
            habit.schedule.endDate = max(calendar.startOfDay(for: endDate), habit.schedule.startDate)
        } else {
            habit.schedule.endDate = nil
        }
        habit.reminder = hasReminder ? ReminderTime(date: reminderDate) : nil
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
                preset("Каждый день", Weekdays.all)
                preset("Будни", Weekdays.workdays)
                preset("Выходные", Weekdays.weekend)
            }
        }
        .padding(.vertical, 4)
    }

    private func preset(_ title: String, _ days: Set<Int>) -> some View {
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
