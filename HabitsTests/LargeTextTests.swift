import XCTest
@testable import Habits

/// 1.7, KAN-116: однобуквенные дни недели для тепловой карты и недели при крупном шрифте.
final class LargeTextTests: XCTestCase {
    func testVeryShortWeekdaysAreSingleLetters() {
        for day in 1...7 {
            let letter = Weekdays.veryShort(day)
            XCTAssertFalse(letter.isEmpty)
            XCTAssertLessThanOrEqual(letter.count, Weekdays.short(day).count)
            XCTAssertLessThanOrEqual(letter.count, 2)
        }
        XCTAssertEqual(Weekdays.veryShort(0), "")
    }

    func testWeekdayVeryShortForDate() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(Fmt.weekdayVeryShort(date), Weekdays.veryShort(Calendar.app.component(.weekday, from: date)))
    }
}
