import SwiftUI

/// Каталог готовых привычек: добавить в одно касание или открыть и настроить.
struct HabitCatalogView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var template: Habit?
    @State private var showingCustom = false
    @State private var showingPaywall = false
    @State private var added = 0

    private var categories: [HabitCatalog.Category] {
        let all = HabitCatalog.categories(isPro: store.data.isPro)
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return all }
        return all.compactMap { category in
            let items = category.items.filter { $0.habit.name.localizedCaseInsensitiveContains(text) }
            return items.isEmpty ? nil : HabitCatalog.Category(id: category.id, title: category.title,
                                                              symbol: category.symbol, items: items)
        }
    }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if query.isEmpty {
                        customCard
                    }
                    ForEach(categories) { category in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(category.title, systemImage: category.symbol)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.leading, 4)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(category.items) { item in
                                    CatalogCard(habit: item.habit, isAdded: isAdded(item.habit),
                                                onOpen: { open(item.habit) },
                                                onAdd: { add(item.habit) })
                                }
                            }
                        }
                    }
                    if categories.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .padding(.top, 40)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(String(localized: "New habit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sensoryFeedback(.success, trigger: added)
            .sheet(item: $template) { habit in
                HabitEditorView(template: habit)
            }
            .sheet(isPresented: $showingCustom) {
                HabitEditorView(habit: nil)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
    }

    private var customCard: some View {
        Button {
            guard store.data.canAddHabit else { showingPaywall = true; return }
            showingCustom = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.accentColor.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom habit")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text("Your own name, icon and schedule")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .card(padding: 14, cornerRadius: 22)
        }
        .buttonStyle(PressableStyle())
    }

    private func isAdded(_ habit: Habit) -> Bool {
        store.data.activeHabits.contains { existing in
            if let language = habit.wordsLanguage { return existing.wordsLanguage == language }
            return existing.name.caseInsensitiveCompare(habit.name) == .orderedSame
        }
    }

    private func open(_ habit: Habit) {
        guard store.data.canAddHabit else { showingPaywall = true; return }
        template = habit
    }

    private func add(_ habit: Habit) {
        guard store.data.canAddHabit else { showingPaywall = true; return }
        var new = habit
        new.id = UUID()
        new.createdAt = Date()
        withAnimation(.snappy) { store.upsert(new) }
        added += 1
        if new.reminder != nil {
            Task {
                await NotificationPlanner.requestAuthorizationIfNeeded()
                await store.reschedule()
            }
        }
    }
}

private struct CatalogCard: View {
    let habit: Habit
    let isAdded: Bool
    var onOpen: () -> Void
    var onAdd: () -> Void

    private var color: Color { Palette.color(habit.colorIndex) }

    private var subtitle: String {
        if let reminder = habit.reminder { return reminder.text }
        if habit.schedule.kind == .weekly { return Fmt.timesPerWeek(habit.schedule.timesPerWeek) }
        if habit.schedule.weekdays.count == 1, let day = habit.schedule.weekdays.first { return Weekdays.short(day) }
        return habit.effectivePartOfDay.title
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    HabitIconView(icon: habit.icon, color: color, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(habit.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())

            Button(action: onAdd) {
                Image(systemName: isAdded ? "checkmark" : "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isAdded ? Color.white : color)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(isAdded ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.15))))
            }
            .buttonStyle(PressableStyle(scale: 0.85))
            .disabled(isAdded)
            .accessibilityLabel(isAdded ? String(localized: "Added") : String(localized: "Add habit"))
        }
        .padding(10)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }
}
