import XCTest
@testable import Habits

/// 1.6, KAN-105: у каждого вида питомца своё имя, опыт и стадия общие.
final class PetNamesTests: XCTestCase {
    /// Данные до 1.6 (без `names`) читаются, прежнее имя остаётся у текущего вида.
    func testOldPetDataKeepsNameForCurrentSpecies() throws {
        let json = """
        {"species":"fox","name":"Рыжик","adoptedAt":0,"feeds":{"2026-01-01":2},"stageReached":{"1":0}}
        """
        let pet = try JSONDecoder().decode(PetState.self, from: Data(json.utf8))
        XCTAssertEqual(pet.species, "fox")
        XCTAssertEqual(pet.name, "Рыжик")
        XCTAssertEqual(pet.names, ["fox": "Рыжик"])
        XCTAssertTrue(pet.isNamed)
        XCTAssertEqual(pet.totalFeeds, 2)
    }

    /// Имена по видам переживают сохранение и чтение.
    func testNamesRoundTrip() throws {
        var pet = PetState(species: "dog", name: "Шарик", adoptedAt: Date(timeIntervalSince1970: 0))
        pet.names = ["cat": "Барсик", "dog": "Шарик"]
        let decoded = try JSONDecoder().decode(PetState.self, from: JSONEncoder().encode(pet))
        XCTAssertEqual(decoded, pet)
    }

    /// Туда и обратно: у каждого вида своё имя, опыт и стадия не меняются.
    @MainActor
    func testSwitchingSpeciesBackAndForth() {
        var data = AppData()
        data.wallet.pet = PetState(species: "cat", name: "Барсик", adoptedAt: Date(), names: ["cat": "Барсик"], feeds: [DayKey.make(Date()): 2])
        let store = HabitStore(inMemory: data)
        let xp = Pets.xp(store.data.wallet.pet!, data: store.data)

        // Новый вид без имени: имя по виду, вид не назван (PetView спросит).
        XCTAssertTrue(store.setPetSpecies(Pets.species("dog")))
        XCTAssertEqual(store.data.wallet.pet?.species, "dog")
        XCTAssertEqual(store.data.wallet.pet?.name, Pets.defaultName(Pets.species("dog")))
        XCTAssertEqual(store.data.wallet.pet?.isNamed, false)
        store.confirmPetName("  Шарик ")
        XCTAssertEqual(store.data.wallet.pet?.name, "Шарик")
        XCTAssertEqual(store.data.wallet.pet?.isNamed, true)

        // Обратно к котику: его имя вернулось, опыт общий.
        XCTAssertTrue(store.setPetSpecies(Pets.species("cat")))
        XCTAssertEqual(store.data.wallet.pet?.name, "Барсик")
        XCTAssertEqual(Pets.xp(store.data.wallet.pet!, data: store.data), xp)

        // Переименование меняет имя только текущего вида.
        store.renamePet("Мурзик")
        XCTAssertEqual(store.data.wallet.pet?.names, ["cat": "Мурзик", "dog": "Шарик"])
        XCTAssertTrue(store.setPetSpecies(Pets.species("dog")))
        XCTAssertEqual(store.data.wallet.pet?.name, "Шарик")
        XCTAssertEqual(Pets.xp(store.data.wallet.pet!, data: store.data), xp)
    }

    /// «Пропустить»: вид получает имя по умолчанию и больше не спрашивает.
    @MainActor
    func testSkipNamingKeepsDefaultName() {
        var data = AppData()
        data.wallet.pet = PetState(species: "cat", name: "Барсик", adoptedAt: Date(), names: ["cat": "Барсик"])
        let store = HabitStore(inMemory: data)
        XCTAssertTrue(store.setPetSpecies(Pets.species("chick")))
        store.confirmPetName(nil)
        let fallback = Pets.defaultName(Pets.species("chick"))
        XCTAssertEqual(store.data.wallet.pet?.names["chick"], fallback)
        XCTAssertEqual(store.data.wallet.pet?.name, fallback)
        XCTAssertEqual(store.data.wallet.pet?.names["cat"], "Барсик")
    }
}
