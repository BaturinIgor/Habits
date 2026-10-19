import SwiftUI

// MARK: - Сводка для ачивок

/// Всё, что нужно для проверки ачивок, считается один раз.
struct AchievementFacts {
    var totalDone = 0
    var bestStreak = 0
    var perfectDays = 0
    var bestPerfectRun = 0
    var earlyChecks = 0
    var lateChecks = 0
    var comebacks = 0
    var habitsCreated = 0
    var notes = 0
    var weeklyGoals = 0
    var minimumChecks = 0
    var freezesUsed = 0

    init(data: AppData, now: Date = Date()) {
        let calendar = Calendar.app
        habitsCreated = data.habits.count
        for (key, entry) in data.checkIns {
            if !(entry.note ?? "").isEmpty { notes += 1 }
            guard entry.status == .done else { continue }
            totalDone += 1
            if entry.isMinimum == true { minimumChecks += 1 }
            // Ранние и поздние отметки считаем только в тот же день, без задним числом.
            let dayPart = key.split(separator: "|").last.map(String.init) ?? ""
            if dayPart == DayKey.make(entry.updatedAt, calendar: calendar) {
                let hour = calendar.component(.hour, from: entry.updatedAt)
                if hour < 8 { earlyChecks += 1 }
                if hour >= 22 { lateChecks += 1 }
            }
        }
        for habit in data.habits {
            let stats = Stats.habit(habit, in: data, now: now, calendar: calendar)
            if !stats.isWeekly { bestStreak = max(bestStreak, stats.bestStreak) }
            weeklyGoals += stats.goalsMet
            comebacks += stats.comebacks
            freezesUsed += stats.frozenDays.count
        }
        // Идеальные дни за последний год.
        let today = calendar.startOfDay(for: now)
        var run = 0
        for offset in (0..<366).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let p = Stats.day(day, in: data, calendar: calendar)
            if p.total > 0 && p.done == p.total {
                perfectDays += 1
                run += 1
                bestPerfectRun = max(bestPerfectRun, run)
            } else if p.total > 0 && day < today {
                run = 0
            }
        }
    }
}

// MARK: - Ачивки

struct Achievement: Identifiable {
    let id: String
    let icon: String
    let color: Color
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let goal: Int
    let value: (AchievementFacts) -> Int

    func progress(_ facts: AchievementFacts) -> Int { min(value(facts), goal) }
    func isUnlocked(_ facts: AchievementFacts) -> Bool { value(facts) >= goal }
}

enum Achievements {
    static let all: [Achievement] = [
        Achievement(id: "first", icon: "sparkles", color: .yellow, title: "First step",
                    detail: "Check off a habit for the first time", goal: 1) { $0.totalDone },
        Achievement(id: "streak3", icon: "flame", color: .orange, title: "Warming up",
                    detail: "Keep a 3-day streak", goal: 3) { $0.bestStreak },
        Achievement(id: "streak7", icon: "flame.fill", color: .orange, title: "A week strong",
                    detail: "Keep a 7-day streak", goal: 7) { $0.bestStreak },
        Achievement(id: "streak30", icon: "bolt.fill", color: .red, title: "Month of power",
                    detail: "Keep a 30-day streak", goal: 30) { $0.bestStreak },
        Achievement(id: "streak100", icon: "crown.fill", color: .purple, title: "Hundred",
                    detail: "Keep a 100-day streak", goal: 100) { $0.bestStreak },
        Achievement(id: "streak365", icon: "star.circle.fill", color: .indigo, title: "A whole year",
                    detail: "Keep a 365-day streak", goal: 365) { $0.bestStreak },
        Achievement(id: "perfectDay", icon: "checkmark.seal.fill", color: .green, title: "Perfect day",
                    detail: "Complete every habit in a day", goal: 1) { $0.perfectDays },
        Achievement(id: "perfectWeek", icon: "calendar.badge.checkmark", color: .mint, title: "Perfect week",
                    detail: "7 perfect days in a row", goal: 7) { $0.bestPerfectRun },
        Achievement(id: "earlyBird", icon: "sunrise.fill", color: .yellow, title: "Early bird",
                    detail: "Check off 10 habits before 8 am", goal: 10) { $0.earlyChecks },
        Achievement(id: "nightOwl", icon: "moon.stars.fill", color: .indigo, title: "Night owl",
                    detail: "Check off 10 habits after 10 pm", goal: 10) { $0.lateChecks },
        Achievement(id: "comeback", icon: "arrow.uturn.up.circle.fill", color: .teal, title: "Comeback",
                    detail: "Return to a habit after a miss", goal: 1) { $0.comebacks },
        Achievement(id: "resilient", icon: "figure.walk.motion", color: .teal, title: "Resilient",
                    detail: "Come back after a miss 10 times", goal: 10) { $0.comebacks },
        Achievement(id: "hundredChecks", icon: "100.circle.fill", color: .blue, title: "Hundred check-ins",
                    detail: "Check off habits 100 times", goal: 100) { $0.totalDone },
        Achievement(id: "thousandChecks", icon: "trophy.fill", color: .yellow, title: "Legend",
                    detail: "Check off habits 1000 times", goal: 1000) { $0.totalDone },
        Achievement(id: "collector", icon: "square.stack.3d.up.fill", color: .pink, title: "Collector",
                    detail: "Create 5 habits", goal: 5) { $0.habitsCreated },
        Achievement(id: "writer", icon: "note.text", color: .brown, title: "Diarist",
                    detail: "Write 10 notes", goal: 10) { $0.notes },
        Achievement(id: "weeklyHero", icon: "calendar", color: .green, title: "Weekly hero",
                    detail: "Reach a weekly goal 4 times", goal: 4) { $0.weeklyGoals },
        Achievement(id: "minimalist", icon: "tortoise.fill", color: .mint, title: "Better than nothing",
                    detail: "Do the minimum version 10 times", goal: 10) { $0.minimumChecks },
        Achievement(id: "frozen", icon: "snowflake", color: .cyan, title: "Ice cold",
                    detail: "Save a streak with a freeze", goal: 1) { $0.freezesUsed },
    ]

    static func unlockedIDs(_ data: AppData) -> Set<String> {
        let facts = AchievementFacts(data: data)
        return Set(all.filter { $0.isUnlocked(facts) }.map(\.id))
    }

    /// Уровень растёт с числом отметок: 5, 20, 45, 80, ... отметок.
    static func level(totalDone: Int) -> (level: Int, progress: Double) {
        let level = Int((Double(totalDone) / 5).squareRoot()) + 1
        let current = 5 * (level - 1) * (level - 1)
        let next = 5 * level * level
        return (level, Double(totalDone - current) / Double(max(1, next - current)))
    }
}

// MARK: - Награды: фоны и аватарки

enum RewardKind { case background, avatar }

/// Как открывается награда.
enum Unlock: Equatable {
    case free
    case achievement(String)
    case pro
}

struct Reward: Identifiable {
    let id: String
    let kind: RewardKind
    let unlock: Unlock
    /// Пользоваться можно только с Pro, даже если открыта ачивкой.
    let needsPro: Bool
    let emoji: String
    let colors: [Color]

    func isAvailable(unlocked: Set<String>, isPro: Bool) -> Bool {
        if needsPro && !isPro { return false }
        switch unlock {
        case .free: return true
        case .pro: return isPro
        case .achievement(let id): return unlocked.contains(id)
        }
    }
}

enum Rewards {
    private static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    static let backgrounds: [Reward] = [
        Reward(id: "default", kind: .background, unlock: .free, needsPro: false, emoji: "", colors: []),
        Reward(id: "sky", kind: .background, unlock: .free, needsPro: false, emoji: "",
               colors: [c(0.55, 0.78, 1), c(0.78, 0.9, 1)]),
        Reward(id: "peach", kind: .background, unlock: .free, needsPro: false, emoji: "",
               colors: [c(1, 0.75, 0.6), c(1, 0.88, 0.8)]),
        Reward(id: "sunrise", kind: .background, unlock: .achievement("streak3"), needsPro: false, emoji: "",
               colors: [c(1, 0.6, 0.4), c(1, 0.85, 0.45)]),
        Reward(id: "mint", kind: .background, unlock: .achievement("perfectDay"), needsPro: false, emoji: "",
               colors: [c(0.5, 0.9, 0.75), c(0.75, 0.95, 0.9)]),
        Reward(id: "candy", kind: .background, unlock: .achievement("collector"), needsPro: false, emoji: "",
               colors: [c(1, 0.6, 0.8), c(0.75, 0.7, 1)]),
        Reward(id: "ocean", kind: .background, unlock: .achievement("hundredChecks"), needsPro: true, emoji: "",
               colors: [c(0.1, 0.45, 0.85), c(0.3, 0.85, 0.9)]),
        Reward(id: "aurora", kind: .background, unlock: .achievement("streak30"), needsPro: true, emoji: "",
               colors: [c(0.2, 0.85, 0.6), c(0.35, 0.4, 0.95), c(0.75, 0.35, 0.9)]),
        Reward(id: "forest", kind: .background, unlock: .achievement("weeklyHero"), needsPro: true, emoji: "",
               colors: [c(0.2, 0.55, 0.35), c(0.6, 0.8, 0.45)]),
        Reward(id: "galaxy", kind: .background, unlock: .achievement("streak365"), needsPro: true, emoji: "",
               colors: [c(0.15, 0.1, 0.4), c(0.55, 0.2, 0.7), c(0.95, 0.45, 0.6)]),
        Reward(id: "neon", kind: .background, unlock: .pro, needsPro: true, emoji: "",
               colors: [c(0.95, 0.2, 0.6), c(0.3, 0.3, 1)]),
        Reward(id: "sunset", kind: .background, unlock: .pro, needsPro: true, emoji: "",
               colors: [c(0.95, 0.35, 0.35), c(1, 0.65, 0.3), c(0.6, 0.3, 0.7)]),
        Reward(id: "lavender", kind: .background, unlock: .pro, needsPro: true, emoji: "",
               colors: [c(0.75, 0.65, 1), c(0.95, 0.8, 1)]),
        Reward(id: "midnight", kind: .background, unlock: .pro, needsPro: true, emoji: "",
               colors: [c(0.05, 0.1, 0.25), c(0.2, 0.25, 0.5)]),
    ]

    static let avatars: [Reward] = [
        avatar("sprout", "🌱", .free), avatar("smile", "🙂", .free), avatar("chick", "🐣", .free),
        avatar("star", "🌟", .achievement("first")),
        avatar("fox", "🦊", .achievement("streak7")),
        avatar("owl", "🦉", .achievement("perfectWeek")),
        avatar("bird", "🐦", .achievement("earlyBird")),
        avatar("phoenix", "🐦‍🔥", .achievement("comeback")),
        avatar("cat", "🐱", .achievement("writer")),
        avatar("turtle", "🐢", .achievement("minimalist")),
        avatar("penguin", "🐧", .achievement("frozen")),
        avatar("bat", "🦇", .achievement("nightOwl"), pro: true),
        avatar("dragon", "🐉", .achievement("streak100"), pro: true),
        avatar("unicorn", "🦄", .achievement("thousandChecks"), pro: true),
        avatar("lion", "🦁", .achievement("resilient"), pro: true),
        avatar("panda", "🐼", .pro), avatar("octopus", "🐙", .pro), avatar("robot", "🤖", .pro),
        avatar("alien", "👽", .pro), avatar("crown", "👑", .pro), avatar("rocket", "🚀", .pro),
    ]

    private static func avatar(_ id: String, _ emoji: String, _ unlock: Unlock, pro: Bool = false) -> Reward {
        Reward(id: id, kind: .avatar, unlock: unlock, needsPro: pro || unlock == .pro, emoji: emoji, colors: [])
    }

    /// Свои фото (Pro), выбираются в профиле.
    static let photoBackground = Reward(id: CustomImages.photoID, kind: .background, unlock: .pro, needsPro: true, emoji: "", colors: [])
    static let photoAvatar = Reward(id: CustomImages.photoID, kind: .avatar, unlock: .pro, needsPro: true, emoji: "🙂", colors: [])

    static func background(_ id: String) -> Reward {
        id == CustomImages.photoID ? photoBackground : backgrounds.first { $0.id == id } ?? backgrounds[0]
    }
    static func avatar(_ id: String) -> Reward {
        id == CustomImages.photoID ? photoAvatar : avatars.first { $0.id == id } ?? avatars[0]
    }

    /// Что награда открывает, для подписи под заблокированной.
    static func achievement(for reward: Reward) -> Achievement? {
        if case .achievement(let id) = reward.unlock { return Achievements.all.first { $0.id == id } }
        return nil
    }
}

// MARK: - Отображение

struct AvatarView: View {
    let reward: Reward
    var size: CGFloat = 36

    var body: some View {
        if reward.id == CustomImages.photoID, let image = CustomImages.shared.avatar {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1.5))
        } else {
            emojiBody
        }
    }

    private var emojiBody: some View {
        Text(reward.emoji)
            .font(.system(size: size * 0.58))
            .frame(width: size, height: size)
            .background(Circle().fill(Color.accentColor.opacity(0.15)))
            .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1.5))
    }
}

/// Фон главного экрана: мягкий градиент поверх системного фона.
struct RewardBackground: View {
    let reward: Reward
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            if reward.id == CustomImages.photoID, let image = CustomImages.shared.background {
                GeometryReader { proxy in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                // Лёгкая дымка, чтобы карточки и текст читались на любом фото.
                Color(uiColor: .systemGroupedBackground).opacity(scheme == .dark ? 0.45 : 0.35)
            } else if !reward.colors.isEmpty {
                LinearGradient(colors: reward.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(scheme == .dark ? 0.35 : 0.45)
            }
        }
        .ignoresSafeArea()
    }
}

struct BackgroundSwatch: View {
    let reward: Reward

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(reward.colors.isEmpty
                  ? AnyShapeStyle(Color(uiColor: .systemGroupedBackground))
                  : AnyShapeStyle(LinearGradient(colors: reward.colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.quaternary, lineWidth: 1))
    }
}
