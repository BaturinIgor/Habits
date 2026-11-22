import SwiftUI

/// Первый запуск (1.7, KAN-121/KAN-122): цель → привычки программы с галочками → итог с коротким
/// знакомством (жесты, пропуски, питомец) → пейволл с «Продолжить бесплатно». Закрытие ведёт на «Сегодня»
/// с созданными привычками. Обновившиеся со старой версии сюда не попадают (OnboardingPlan.shouldShowOnboarding).
struct OnboardingView: View {
    typealias Step = OnboardingPlan.Step

    @Environment(HabitStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var step: Step
    @State private var goal: OnboardingGoal?
    /// Привычки выбранной программы (с новыми id) и отмеченные галочкой.
    @State private var program: [Habit] = []
    @State private var selected: Set<UUID> = []
    /// Копия в iCloud, найденная при первом запуске (например, на новом телефоне).
    @State private var cloudCopy: (info: CloudBackup.Info, data: AppData)?
    @State private var startedAt = Date()
    @State private var created = 0

    /// step и goal задаются для макетов (DesignGallery); в приложении онбординг всегда начинается с цели.
    init(step: Step = .goal, goal: OnboardingGoal? = nil) {
        _step = State(initialValue: step)
        _goal = State(initialValue: goal)
    }

    var body: some View {
        Group {
            if step == .paywall {
                PaywallView(source: .onboarding) { finish() }
            } else {
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        Group {
                            switch step {
                            case .goal: goalStep
                            case .habits: habitsStep
                            default: summaryStep
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    footer
                }
                .background(AppBackground())
            }
        }
        .uiTestScreen("onboarding")
        .analyticsScreen(.onboarding)
        .onAppear {
            if let goal, program.isEmpty { choose(goal) }
        }
        .task(id: step) { Analytics.shared.onboardingStep(step.rawValue) }
        .task {
            // Новый телефон или переустановка: предлагаем вернуть копию из iCloud.
            guard CloudBackup.isAvailable, store.data.habits.isEmpty else { return }
            cloudCopy = try? await CloudBackup.shared.fetchLatest()
        }
        .alert(
            "Restore your habits?",
            isPresented: Binding(get: { cloudCopy != nil }, set: { if !$0 { cloudCopy = nil } }),
            presenting: cloudCopy
        ) { copy in
            Button("Restore") {
                CloudBackup.shared.restore(copy.data)
                finish(restored: true)
            }
            Button("Start over", role: .cancel) {}
        } message: { copy in
            Text("There's a backup in your iCloud from \(Fmt.backupDate(copy.info.date)). Habits in it: \(copy.info.habits).")
        }
    }

    // MARK: Шапка и кнопки

    private var header: some View {
        HStack {
            if step != .goal {
                Button {
                    withAnimation(.snappy) { step = Step(rawValue: step.rawValue - 1) ?? .goal }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
                .accessibilityIdentifier("onboarding.back")
            }
            Spacer()
            // Прогресс: три шага до старта.
            HStack(spacing: 6) {
                ForEach([Step.goal, .habits, .summary], id: \.self) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: item == step ? 22 : 8, height: 8)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(String(localized: "Step \(step.rawValue) of 3"))
            Spacer()
            if step != .goal {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: next) {
                Text(step == .summary ? String(localized: "Let's go") : String(localized: "Continue"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .glassButtonStyle(prominent: true)
            .disabled(!canContinue)
            .accessibilityIdentifier("onboarding.next")
            if step != .summary {
                Button("Skip") { finish(skippedAt: step) }
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("onboarding.skip")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var canContinue: Bool {
        switch step {
        case .goal: goal != nil
        case .habits: !selected.isEmpty
        default: true
        }
    }

    // MARK: Шаг 1: цель

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to Habit Tracker")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text("What do you want to work on?")
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Pick a goal and we'll set up your first habits. You can change everything later.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)

            let columns = typeSize.isAccessibilitySize
                ? [GridItem(.flexible())]
                : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(OnboardingGoal.allCases) { item in
                    goalCard(item)
                }
            }
        }
    }

    private func goalCard(_ item: OnboardingGoal) -> some View {
        let isOn = goal == item
        let color = Palette.color(item.colorIndex)
        return Button {
            withAnimation(.snappy) { choose(item) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(color.gradient))
                    Spacer(minLength: 4)
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .strokeBorder(isOn ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.subtitle)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("onboarding.goal.\(item.rawValue)")
        .sensoryFeedback(.selection, trigger: isOn)
    }

    // MARK: Шаг 2: привычки программы

    private var habitsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                if let goal {
                    Label(goal.title, systemImage: goal.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Text("Your first habits")
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Uncheck what you don't need. You can add more from the catalog later.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)

            VStack(spacing: 10) {
                ForEach(program) { habit in
                    habitRow(habit)
                }
            }

            if let slots = OnboardingPlan.freeSlots(in: store.data), slots < program.count {
                Text("The free version has up to 5 active habits.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func habitRow(_ habit: Habit) -> some View {
        let isOn = selected.contains(habit.id)
        let color = Palette.color(habit.colorIndex)
        return Button {
            withAnimation(.snappy) { toggle(habit) }
        } label: {
            HStack(spacing: 14) {
                HabitIconView(icon: habit.icon, color: color, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.subtitle(habit))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isOn ? color : Color.secondary.opacity(0.5))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(!isOn && !canSelectMore)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(habit.name)
        .accessibilityValue(Self.subtitle(habit))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .sensoryFeedback(.selection, trigger: isOn)
    }

    /// Когда напоминаем или как часто: как в каталоге.
    private static func subtitle(_ habit: Habit) -> String {
        if let reminder = habit.reminder { return reminder.text }
        if habit.schedule.kind == .weekly { return Fmt.timesPerWeek(habit.schedule.timesPerWeek) }
        return habit.effectivePartOfDay.title
    }

    private var canSelectMore: Bool {
        guard let slots = OnboardingPlan.freeSlots(in: store.data) else { return true }
        return selected.count < slots
    }

    // MARK: Шаг 3: итог и знакомство

    private var chosen: [Habit] { program.filter { selected.contains($0.id) } }

    private var summaryStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your plan is ready")
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Start with one check-in today. Small steps count.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(chosen) { habit in
                    HStack(spacing: 12) {
                        HabitIconView(icon: habit.icon, color: Palette.color(habit.colorIndex), size: 32)
                        Text(habit.name)
                            .font(.body.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16, cornerRadius: 22)

            Text("How it works")
                .font(.title3.weight(.bold))
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 16) {
                tip("hand.draw.fill", .orange,
                    "Tap the circle or swipe right to check off. Swipe left to skip, add a note or edit. Press and hold to reorder.")
                tip("snowflake", .cyan,
                    "Two misses a month won't break your streak, and a minimum version still counts on hard days.")
                tip("pawprint.fill", .pink,
                    "Earn sparks for check-ins, spend them in the shop and raise a pet that grows with your habits.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16, cornerRadius: 22)
        }
    }

    private func tip(_ icon: String, _ color: Color, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(color.gradient))
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Действия

    private func choose(_ item: OnboardingGoal) {
        guard goal != item || program.isEmpty else { return }
        goal = item
        program = OnboardingPlan.habits(for: item, isPro: store.data.isPro)
        // Всё отмечено сразу, в бесплатной версии — сколько помещается в лимит.
        let slots = OnboardingPlan.freeSlots(in: store.data) ?? program.count
        selected = Set(program.prefix(slots).map(\.id))
    }

    private func toggle(_ habit: Habit) {
        if selected.contains(habit.id) {
            selected.remove(habit.id)
        } else if canSelectMore {
            selected.insert(habit.id)
        }
    }

    private func next() {
        switch step {
        case .goal: withAnimation(.snappy) { step = .habits }
        case .habits: withAnimation(.snappy) { step = .summary }
        default: start()
        }
    }

    /// «Начать»: создаём привычки, потом пейволл (один раз, без Pro) или сразу «Сегодня».
    private func start() {
        let habits = OnboardingPlan.habitsToAdd(chosen, to: store.data)
        for habit in habits { store.upsert(habit, source: .onboarding) }
        created = habits.count
        if let goal { Analytics.shared.send(.onboardingGoal(goal: goal.rawValue, habits: habits.count)) }
        if OnboardingPlan.shouldShowPaywall(store.data) {
            store.updateSettings { $0.onboardingPaywallSeen = true }
            withAnimation(.snappy) { step = .paywall }
        } else {
            finish()
        }
    }

    private func finish(restored: Bool = false, skippedAt: Step? = nil) {
        if let skippedAt { Analytics.shared.send(.onboardingSkipped(step: skippedAt.rawValue)) }
        Analytics.shared.send(.onboardingCompleted(seconds: Int(Date().timeIntervalSince(startedAt)), restoredFromCloud: restored))
        let firstDay = !restored && OnboardingPlan.startsFirstDay(created: created, data: store.data)
        store.updateSettings {
            $0.onboardingDone = true
            $0.whatsNewSeen = WhatsNewView.version
            $0.firstDayGuide = firstDay
            // Подсказку о жестах заменяет подсказка первого дня, а знакомство уже рассказало о жестах.
            if firstDay { $0.gestureHintShown = true }
        }
        // Разрешение на уведомления не спрашиваем на старте: после первой отметки (карточка на «Сегодня»)
        // или когда человек сам выбирает время напоминания.
        Task { await store.reschedule() }
    }
}
