import SwiftUI

// MARK: - Искры

/// Откуда взялись искры. Всё считается из истории, поэтому снятая отметка
/// сразу забирает свою искру, а отметки задним числом не приносят ничего.
struct SparkReport: Equatable {
    var checks = 0
    var perfectDays = 0
    var streaks = 0
    var comebacks = 0
    var achievements = 0
    var gifts = 0
    /// Сохранено с удалённых привычек.
    var kept = 0
    /// Подарки питомца за активные дни.
    var pet = 0
    var total: Int { checks + perfectDays + streaks + comebacks + achievements + gifts + kept + pet }
}

enum Sparks {
    static let dailyCap = 10
    static let proDailyCap = 15
    static let perfectDayBonus = 5
    static let weekStreakBonus = 10
    static let monthStreakBonus = 50
    static let comebackBonus = 3
    static let achievementBonus = 20
    static let proMonthlyGift = 100
    static let freezePrice = 30
    static let maxExtraFreezes = 2
    static let feedPrice = 5
    static let feedsPerDay = 3
    /// Сколько опыта даёт одно кормление.
    static let feedXP = 3

    /// Отметка честная, если поставлена в тот же день или на следующий.
    static func isOnTime(_ entry: CheckIn, day: String, calendar: Calendar = .app) -> Bool {
        guard let date = DayKey.date(day, calendar: calendar),
              let limit = calendar.date(byAdding: .day, value: 2, to: date) else { return false }
        return entry.updatedAt < limit
    }

    /// Честные отметки по дням (с учётом дневного лимита), начиная с даты.
    static func checksPerDay(_ data: AppData, from start: Date? = nil, calendar: Calendar = .app) -> [String: Int] {
        let habits = Dictionary(data.habits.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let startKey = start.map { DayKey.make($0, calendar: calendar) }
        var perDay: [String: Int] = [:]
        for (key, entry) in data.checkIns where entry.status == .done {
            let parts = key.split(separator: "|").map(String.init)
            guard parts.count == 2, let id = UUID(uuidString: parts[0]), let habit = habits[id],
                  let date = DayKey.date(parts[1], calendar: calendar) else { continue }
            if let startKey, parts[1] < startKey { continue }
            guard habit.isScheduled(on: date, calendar: calendar), isOnTime(entry, day: parts[1], calendar: calendar) else { continue }
            perDay[parts[1], default: 0] += 1
        }
        for (day, count) in perDay {
            let month = String(day.prefix(7))
            let cap = data.wallet.proMonths.contains(month) ? proDailyCap : dailyCap
            perDay[day] = min(count, cap)
        }
        return perDay
    }

    static func balance(earned: Int, data: AppData) -> Int { max(0, earned - data.wallet.spent) }

    /// Баланс по последнему подсчёту приложения (для виджета, где нет полного подсчёта).
    static func snapshotBalance(_ data: AppData) -> Int { max(0, data.wallet.earnedSnapshot - data.wallet.spent) }
}

/// Значок искр с числом.
struct SparkBadge: View {
    let amount: Int
    var font: Font = .subheadline.weight(.bold)

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
            Text(verbatim: "\(amount)")
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(font)
        .lineLimit(1)
        // Не даём панели инструментов сжать число до одной цифры.
        .fixedSize()
    }
}

// MARK: - Питомцы

struct PetSpecies: Identifiable {
    let id: String
    let baby: String
    let adult: String
    let title: LocalizedStringResource
    /// nil - бесплатно.
    let price: Int?
    let needsPro: Bool
}

enum PetStage: Int, CaseIterable, Comparable {
    static func < (a: PetStage, b: PetStage) -> Bool { a.rawValue < b.rawValue }

    case egg, baby, young, adult, legend

    var threshold: Int {
        switch self {
        case .egg: 0
        case .baby: 10
        case .young: 50
        case .adult: 150
        case .legend: 400
        }
    }

    var title: String {
        switch self {
        case .egg: String(localized: "Egg")
        case .baby: String(localized: "Baby")
        case .young: String(localized: "Young")
        case .adult: String(localized: "Grown-up")
        case .legend: String(localized: "Legend")
        }
    }

    static func stage(xp: Int) -> PetStage {
        allCases.last { xp >= $0.threshold } ?? .egg
    }

    var next: PetStage? { PetStage(rawValue: rawValue + 1) }

    /// Сколько искр питомец приносит каждый день, когда отмечена хотя бы одна привычка.
    var dailyGift: Int {
        switch self {
        case .egg: 0
        case .baby: 1
        case .young: 2
        case .adult: 3
        case .legend: 5
        }
    }

    /// Сколько дополнительных заморозок серии в месяц даёт питомец.
    var bonusFreezes: Int {
        switch self {
        case .egg, .baby, .young: 0
        case .adult: 1
        case .legend: 2
        }
    }

    /// Что даёт стадия, одной строкой.
    var perks: String {
        switch self {
        case .egg: String(localized: "Hatches after a few check-ins")
        case .baby: String(localized: "+1 spark every active day")
        case .young: String(localized: "+2 sparks every active day")
        case .adult: String(localized: "+3 sparks every active day and +1 streak freeze a month")
        case .legend: String(localized: "+5 sparks every active day and +2 streak freezes a month")
        }
    }
}

enum PetMood {
    case happy, calm, sad, lonely, sleeping

    var title: String {
        switch self {
        case .happy: String(localized: "Happy")
        case .calm: String(localized: "Waiting for you")
        case .sad: String(localized: "Sad")
        case .lonely: String(localized: "Misses you a lot")
        case .sleeping: String(localized: "Sleeping")
        }
    }

    var bubble: String {
        switch self {
        case .happy: "💛"
        case .calm: "🙂"
        case .sad: "😢"
        case .lonely: "💔"
        case .sleeping: "💤"
        }
    }
}

enum Pets {
    static let all: [PetSpecies] = [
        PetSpecies(id: "cat", baby: "🐱", adult: "🐈", title: "Cat", price: nil, needsPro: false),
        PetSpecies(id: "dog", baby: "🐶", adult: "🐕", title: "Dog", price: nil, needsPro: false),
        PetSpecies(id: "chick", baby: "🐣", adult: "🐥", title: "Chick", price: nil, needsPro: false),
        PetSpecies(id: "bunny", baby: "🐰", adult: "🐇", title: "Bunny", price: 100, needsPro: false),
        PetSpecies(id: "turtle", baby: "🐢", adult: "🐢", title: "Turtle", price: 120, needsPro: false),
        PetSpecies(id: "fox", baby: "🦊", adult: "🦊", title: "Fox", price: 150, needsPro: false),
        PetSpecies(id: "panda", baby: "🐼", adult: "🐼", title: "Panda", price: 200, needsPro: false),
        PetSpecies(id: "owl", baby: "🦉", adult: "🦉", title: "Owl", price: 250, needsPro: false),
        PetSpecies(id: "dragon", baby: "🐲", adult: "🐉", title: "Dragon", price: nil, needsPro: true),
        PetSpecies(id: "unicorn", baby: "🦄", adult: "🦄", title: "Unicorn", price: nil, needsPro: true),
        PetSpecies(id: "phoenix", baby: "🐣", adult: "🐦‍🔥", title: "Phoenix", price: nil, needsPro: true),
    ]

    static func species(_ id: String) -> PetSpecies { all.first { $0.id == id } ?? all[0] }

    static func isOwned(_ species: PetSpecies, data: AppData) -> Bool {
        if species.needsPro { return data.isPro }
        return species.price == nil || data.wallet.ownedPets.contains(species.id)
    }

    /// Стадия питомца. Достигнутая стадия не теряется, даже если снять отметки.
    static func stage(_ pet: PetState, data: AppData) -> PetStage {
        max(PetStage.stage(xp: xp(pet, data: data)), pet.highestReached ?? .egg)
    }

    /// Стадия, которая была у питомца в этот день (по датам достижения стадий).
    static func stage(onDay day: String, pet: PetState, calendar: Calendar = .app) -> PetStage {
        var result = PetStage.egg
        for (raw, date) in pet.stageReached {
            guard let stage = Int(raw).flatMap(PetStage.init(rawValue:)), stage > result,
                  DayKey.make(date, calendar: calendar) <= day else { continue }
            result = stage
        }
        return result
    }

    /// Дополнительные заморозки от питомца в месяце "yyyy-MM".
    static func bonusFreezes(month: String, pet: PetState?, calendar: Calendar = .app) -> Int {
        guard let pet else { return 0 }
        var best = PetStage.egg
        for (raw, date) in pet.stageReached {
            guard let stage = Int(raw).flatMap(PetStage.init(rawValue:)), stage > best,
                  Wallet.monthKey(date, calendar: calendar) <= month else { continue }
            best = stage
        }
        return best.bonusFreezes
    }

    /// Опыт: честные отметки с момента появления питомца плюс кормления.
    static func xp(_ pet: PetState, data: AppData) -> Int {
        Sparks.checksPerDay(data, from: pet.adoptedAt).values.reduce(0, +) + pet.totalFeeds * Sparks.feedXP + data.wallet.keptPetXP
    }

    static func mood(_ pet: PetState, data: AppData, now: Date = Date(), calendar: Calendar = .app) -> PetMood {
        let today = calendar.startOfDay(for: now)
        let todayKey = DayKey.make(today, calendar: calendar)
        let hour = calendar.component(.hour, from: now)
        let doneDays = Set(data.checkIns.filter { $0.value.status == .done }.compactMap { $0.key.split(separator: "|").last.map(String.init) })
        let fedToday = pet.feeds[todayKey, default: 0] > 0
        let activeToday = doneDays.contains(todayKey) || fedToday
        if activeToday {
            return hour >= 23 || hour < 6 ? .sleeping : .happy
        }
        // Сколько дней без отметок и кормлений.
        var gap = 0
        var day = today
        let start = calendar.startOfDay(for: pet.adoptedAt)
        while gap < 7, let prev = calendar.date(byAdding: .day, value: -1, to: day), prev >= start {
            let key = DayKey.make(prev, calendar: calendar)
            if doneDays.contains(key) || pet.feeds[key, default: 0] > 0 { break }
            gap += 1
            day = prev
        }
        if hour >= 23 || hour < 6 { return .sleeping }
        switch gap {
        case 0: return .calm
        case 1...2: return .sad
        default: return .lonely
        }
    }

    static let phrases: [LocalizedStringResource] = [
        "You're doing great!", "One more habit?", "I believe in you!", "Small steps add up.",
        "Let's keep the streak going!", "I'm proud of you!", "Don't forget about me!", "Today is a good day.",
    ]
}

/// Питомец: эмодзи по виду и стадии, настроение и украшения.
struct PetAvatar: View {
    let pet: PetState
    let stage: PetStage
    let mood: PetMood
    var size: CGFloat = 120
    @State private var bounce = false

    var body: some View {
        let species = Pets.species(pet.species)
        let emoji = stage == .egg ? "🥚" : (stage.rawValue >= PetStage.adult.rawValue ? species.adult : species.baby)
        let scale: CGFloat = switch stage {
        case .egg: 0.6
        case .baby: 0.62
        case .young: 0.75
        case .adult, .legend: 0.86
        }
        ZStack {
            if stage == .legend {
                Circle()
                    .fill(RadialGradient(colors: [.yellow.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: size * 0.6))
                    .scaleEffect(bounce ? 1.08 : 0.95)
            }
            Text(emoji)
                .font(.system(size: size * scale))
                .saturation(mood == .lonely ? 0.3 : (mood == .sad ? 0.7 : 1))
                .opacity(mood == .sleeping ? 0.75 : 1)
                .offset(y: mood == .happy && bounce ? -size * 0.04 : 0)
                .rotationEffect(.degrees(stage == .egg && bounce ? 4 : (stage == .egg ? -4 : 0)))
            if stage == .legend {
                Text(verbatim: "👑")
                    .font(.system(size: size * 0.24))
                    .offset(x: size * 0.05, y: -size * 0.42)
            } else if stage == .adult {
                Text(verbatim: "🎀")
                    .font(.system(size: size * 0.2))
                    .offset(x: size * 0.28, y: -size * 0.32)
            }
            Text(mood.bubble)
                .font(.system(size: size * 0.18))
                .padding(size * 0.04)
                .background(Circle().fill(.background).shadow(color: .black.opacity(0.12), radius: 3, y: 1))
                .offset(x: size * 0.36, y: size * 0.32)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: mood == .sleeping ? 2.4 : 1.1).repeatForever(autoreverses: true)) {
                bounce = true
            }
        }
    }
}
