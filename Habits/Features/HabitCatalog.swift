import Foundation

/// Готовые привычки, которые добавляются в одно касание.
enum HabitCatalog {
    struct Category: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let items: [Item]
    }

    struct Item: Identifiable {
        let id: String
        let habit: Habit
    }

    private static func time(_ hour: Int, _ minute: Int = 0) -> ReminderTime {
        ReminderTime(hour: hour, minute: minute)
    }

    private static func weekly(_ times: Int) -> HabitSchedule {
        HabitSchedule(kind: .weekly, timesPerWeek: times)
    }

    private static func item(_ id: String, _ name: String, _ symbol: String, _ color: Int,
                             schedule: HabitSchedule = HabitSchedule(),
                             reminder: ReminderTime? = nil,
                             part: PartOfDay = .anytime,
                             target: Int? = nil, unit: String? = nil, isPro: Bool) -> Item {
        Item(id: id, habit: Habit(
            name: name, icon: .symbol(symbol), colorIndex: color, schedule: schedule,
            reminder: reminder, partOfDay: reminder == nil ? part : nil,
            target: isPro ? target : nil, unit: isPro ? unit : nil
        ))
    }

    /// Привычка изучения слов для выбранного языка.
    static func words(_ language: String, perDay: Int = 10) -> Habit {
        let colors = [6, 4, 8, 0, 1, 3, 9, 10, 5, 2, 7, 11, 6, 4]
        let index = WordLanguage.codes.firstIndex(of: language) ?? 0
        return Habit(name: WordLanguage.habitName(language), icon: .symbol("character.book.closed.fill"),
                     colorIndex: colors[index % colors.count], reminder: ReminderTime(hour: 20, minute: 0),
                     wordsLanguage: language, wordsPerDay: perDay)
    }

    static func categories(isPro: Bool) -> [Category] {
        let p = isPro
        return [
            Category(id: "languages", title: String(localized: "Languages"), symbol: "character.bubble.fill",
                     items: WordLanguage.learnable.map { Item(id: "words-" + $0, habit: words($0)) }),
            Category(id: "health", title: String(localized: "Health"), symbol: "heart.fill", items: [
                item("water", String(localized: "Drink water"), "drop.fill", 5, target: 8, unit: String(localized: "glasses"), isPro: p),
                item("vitamins", String(localized: "Take vitamins"), "pills.fill", 2, reminder: time(9), isPro: p),
                item("steps", String(localized: "Walk 10,000 steps"), "figure.walk", 3, part: .afternoon, isPro: p),
                item("veggies", String(localized: "Eat vegetables and fruit"), "carrot.fill", 3, isPro: p),
                item("sleep", String(localized: "Go to bed on time"), "bed.double.fill", 7, reminder: time(22, 30), isPro: p),
                item("wake", String(localized: "Wake up early"), "alarm.fill", 1, reminder: time(7), isPro: p),
                item("floss", String(localized: "Brush and floss"), "mouth.fill", 4, part: .evening, isPro: p),
                item("skin", String(localized: "Skin care"), "hands.and.sparkles.fill", 9, part: .evening, isPro: p),
            ]),
            Category(id: "fitness", title: String(localized: "Fitness"), symbol: "figure.run", items: [
                item("workout", String(localized: "Workout"), "dumbbell.fill", 0, schedule: weekly(3), reminder: time(19), isPro: p),
                item("exercises", String(localized: "Morning exercises"), "figure.strengthtraining.functional", 1, reminder: time(7, 30), isPro: p),
                item("run", String(localized: "Run"), "figure.run", 10, schedule: weekly(3), part: .morning, isPro: p),
                item("stretch", String(localized: "Stretch"), "figure.flexibility", 4, part: .evening, isPro: p),
                item("yoga", String(localized: "Yoga"), "figure.yoga", 8, schedule: weekly(3), isPro: p),
                item("pushups", String(localized: "Push-ups"), "figure.strengthtraining.traditional", 0, target: 20, unit: String(localized: "times"), isPro: p),
                item("bike", String(localized: "Cycling"), "bicycle", 3, schedule: weekly(2), isPro: p),
                item("swim", String(localized: "Swimming"), "figure.pool.swim", 5, schedule: weekly(2), isPro: p),
            ]),
            Category(id: "mind", title: String(localized: "Learning"), symbol: "graduationcap.fill", items: [
                item("read", String(localized: "Read"), "book.fill", 7, reminder: time(21), isPro: p),
                item("study", String(localized: "Study for 30 minutes"), "graduationcap.fill", 6, isPro: p),
                item("music", String(localized: "Practice an instrument"), "guitars.fill", 9, isPro: p),
                item("journal", String(localized: "Keep a journal"), "book.closed.fill", 8, part: .evening, isPro: p),
                item("podcast", String(localized: "Listen to a podcast"), "headphones", 4, isPro: p),
                item("draw", String(localized: "Draw"), "paintbrush.fill", 9, isPro: p),
            ]),
            Category(id: "calm", title: String(localized: "Mindfulness"), symbol: "leaf.fill", items: [
                item("meditate", String(localized: "Meditate"), "figure.mind.and.body", 4, reminder: time(8), isPro: p),
                item("gratitude", String(localized: "Write down 3 good things"), "heart.text.square.fill", 9, part: .evening, isPro: p),
                item("breathe", String(localized: "Breathing exercise"), "lungs.fill", 5, isPro: p),
                item("outside", String(localized: "Spend time outdoors"), "tree.fill", 3, part: .afternoon, isPro: p),
                item("nophone", String(localized: "No phone before bed"), "iphone.slash", 7, part: .evening, isPro: p),
            ]),
            Category(id: "work", title: String(localized: "Productivity"), symbol: "checklist", items: [
                item("plan", String(localized: "Plan the day"), "checklist", 6, reminder: time(8, 30), isPro: p),
                item("bed", String(localized: "Make the bed"), "sun.horizon.fill", 2, part: .morning, isPro: p),
                item("tidy", String(localized: "Tidy up for 10 minutes"), "basket.fill", 1, part: .evening, isPro: p),
                item("focus", String(localized: "Focus for an hour"), "timer", 6, isPro: p),
                item("inbox", String(localized: "Clear your inbox"), "tray.fill", 11, isPro: p),
                item("review", String(localized: "Weekly review"), "calendar", 7, schedule: HabitSchedule(weekdays: [1]), reminder: time(18), isPro: p),
            ]),
            Category(id: "money", title: String(localized: "Finance"), symbol: "banknote.fill", items: [
                item("expenses", String(localized: "Track expenses"), "creditcard.fill", 3, part: .evening, isPro: p),
                item("save", String(localized: "Put money aside"), "banknote.fill", 3, isPro: p),
                item("impulse", String(localized: "No impulse purchases"), "cart.badge.minus", 10, isPro: p),
            ]),
            Category(id: "quit", title: String(localized: "Break bad habits"), symbol: "nosign", items: [
                item("smoking", String(localized: "No smoking"), "nosign", 10, isPro: p),
                item("alcohol", String(localized: "No alcohol"), "wineglass.fill", 10, isPro: p),
                item("sweets", String(localized: "No sweets"), "birthday.cake.fill", 9, isPro: p),
                item("social", String(localized: "Less social media"), "hand.raised.fill", 11, isPro: p),
                item("fastfood", String(localized: "No fast food"), "takeoutbag.and.cup.and.straw.fill", 1, isPro: p),
            ]),
            Category(id: "people", title: String(localized: "Relationships"), symbol: "person.2.fill", items: [
                item("family", String(localized: "Call family"), "phone.fill", 3, schedule: weekly(2), isPro: p),
                item("friend", String(localized: "Message a friend"), "message.fill", 5, isPro: p),
                item("kind", String(localized: "Do a good deed"), "heart.fill", 0, isPro: p),
            ]),
        ]
    }
}
