import Foundation

/// Кошелёк искр и питомец. Заработанное считается из истории отметок,
/// здесь хранится только потраченное и купленное.
struct Wallet: Codable, Hashable {
    var spent = 0
    /// Купленные за искры фоны и аватарки.
    var purchases: [String] = []
    /// Докупленные заморозки: "yyyy-MM" -> сколько.
    var extraFreezes: [String: Int] = [:]
    /// Месяцы, за которые получен подарок Pro ("yyyy-MM"). В эти месяцы выше и дневной лимит искр.
    var proMonths: [String] = []
    var pet: PetState?
    /// Купленные виды питомцев.
    var ownedPets: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spent = try c.decodeIfPresent(Int.self, forKey: .spent) ?? 0
        purchases = try c.decodeIfPresent([String].self, forKey: .purchases) ?? []
        extraFreezes = try c.decodeIfPresent([String: Int].self, forKey: .extraFreezes) ?? [:]
        proMonths = try c.decodeIfPresent([String].self, forKey: .proMonths) ?? []
        pet = try? c.decodeIfPresent(PetState.self, forKey: .pet)
        ownedPets = try c.decodeIfPresent([String].self, forKey: .ownedPets) ?? []
    }

    static func monthKey(_ date: Date, calendar: Calendar = .app) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
}

struct PetState: Codable, Hashable {
    var species: String
    var name: String
    var adoptedAt: Date
    /// Кормления по дням: "yyyy-MM-dd" -> сколько раз.
    var feeds: [String: Int] = [:]

    var totalFeeds: Int { feeds.values.reduce(0, +) }
}
