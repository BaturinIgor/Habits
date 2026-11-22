import XCTest
@testable import Habits

/// 1.7, KAN-115 и KAN-117: подписи VoiceOver.
final class AccessibilityLabelTests: XCTestCase {
    private var cat: PetSpecies { Pets.species("cat") }

    /// Подпись аватара начинается с имени: «Whiskers, Котик, Подросток, Ждёт тебя».
    func testPetAvatarLabelStartsWithName() {
        let text = PetAvatar.accessibilityText(name: "Whiskers", species: cat, stage: .young, mood: .calm)
        let expected = ["Whiskers", String(localized: cat.title), PetStage.young.title, PetMood.calm.title].joined(separator: ", ")
        XCTAssertEqual(text, expected)
    }

    /// Имя по умолчанию совпадает с названием вида, второй раз его не читаем.
    func testPetAvatarLabelSkipsDefaultName() {
        let text = PetAvatar.accessibilityText(name: Pets.defaultName(cat), species: cat, stage: .baby, mood: .happy)
        XCTAssertEqual(text, [String(localized: cat.title), PetStage.baby.title, PetMood.happy.title].joined(separator: ", "))
    }

    /// Пустое имя (или одни пробелы) не даёт лишней запятой в начале.
    func testPetAvatarLabelWithBlankName() {
        let text = PetAvatar.accessibilityText(name: "  ", species: cat, stage: .egg, mood: .sleeping)
        XCTAssertTrue(text.hasPrefix(String(localized: cat.title)))
    }

    /// У каждого цвета палитры есть своё название для VoiceOver.
    func testEveryPaletteColorHasName() {
        XCTAssertEqual(Palette.names.count, Palette.colors.count)
        XCTAssertEqual(Set(Palette.names.map { String(localized: $0) }).count, Palette.colors.count)
    }

    /// Полное название есть у всех семи дней и не короче краткого.
    func testFullWeekdayNames() {
        for day in 1...7 {
            XCTAssertFalse(Weekdays.full(day).isEmpty)
            XCTAssertGreaterThanOrEqual(Weekdays.full(day).count, Weekdays.short(day).count)
        }
        XCTAssertEqual(Weekdays.full(8), "")
    }
}
