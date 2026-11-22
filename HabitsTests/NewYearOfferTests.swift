import StoreKit
import StoreKitTest
import XCTest
@testable import Habits

/// 1.7, KAN-125: новогоднее предложение видно только в дни акции и только без Pro,
/// цена со скидкой и покупка по коду — через StoreKit-конфиг HabitsTests/Habits.storekit.
final class NewYearOfferTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Даты и Pro

    func testHiddenBeforeStart() {
        XCTAssertFalse(NewYearOffer.isAvailable(now: date(2026, 12, 19, 23, 59), isPro: false, calendar: calendar))
        XCTAssertFalse(NewYearOffer.isAvailable(now: date(2026, 11, 22), isPro: false, calendar: calendar))
    }

    func testShownFromFirstToLastDayInclusive() {
        XCTAssertTrue(NewYearOffer.isAvailable(now: date(2026, 12, 20, 0, 0), isPro: false, calendar: calendar))
        XCTAssertTrue(NewYearOffer.isAvailable(now: date(2026, 12, 31, 23, 30), isPro: false, calendar: calendar))
        XCTAssertTrue(NewYearOffer.isAvailable(now: date(2027, 1, 1), isPro: false, calendar: calendar))
        XCTAssertTrue(NewYearOffer.isAvailable(now: date(2027, 1, 10, 23, 59), isPro: false, calendar: calendar))
    }

    func testHiddenAfterEnd() {
        XCTAssertFalse(NewYearOffer.isAvailable(now: date(2027, 1, 11, 0, 0), isPro: false, calendar: calendar))
        XCTAssertFalse(NewYearOffer.isAvailable(now: date(2027, 12, 25), isPro: false, calendar: calendar))
    }

    func testHiddenWithPro() {
        XCTAssertFalse(NewYearOffer.isAvailable(now: date(2026, 12, 25), isPro: true, calendar: calendar))
    }

    /// Конфиг акции согласован: подписка из списка Pro, код по правилам App Store (буквы и цифры, до 64).
    @MainActor
    func testConfigIsConsistent() {
        XCTAssertEqual(NewYearOffer.productID, ProStore.yearlyID)
        XCTAssertTrue((1...99).contains(NewYearOffer.discountPercent))
        XCTAssertTrue(NewYearOffer.code.count <= 64)
        XCTAssertTrue(NewYearOffer.code.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) })
        let interval = NewYearOffer.interval(calendar: calendar)
        XCTAssertNotNil(interval)
        XCTAssertEqual(interval.map { Int($0.duration / 86_400) }, 22)
    }

    // MARK: - StoreKit

    private func makeSession() throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Habits", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    /// Обычная цена года и цена первого года со скидкой приходят из StoreKit; скидка совпадает с конфигом.
    func testDiscountedPriceComesFromStoreKit() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let products = try await Product.products(for: [NewYearOffer.productID])
        let yearly = try XCTUnwrap(products.first)
        let discounted = try XCTUnwrap(NewYearOffer.discountedPrice(of: yearly))
        XCTAssertFalse(discounted.isEmpty)
        XCTAssertNotEqual(discounted, yearly.displayPrice)

        let offer = try XCTUnwrap(yearly.subscription?.promotionalOffers.first { $0.id == NewYearOffer.priceOfferID })
        XCTAssertEqual(offer.paymentMode, .payUpFront)
        XCTAssertEqual(offer.period.unit, .year)
        let ratio = NSDecimalNumber(decimal: offer.price / yearly.price).doubleValue
        XCTAssertEqual(ratio, 1 - Double(NewYearOffer.discountPercent) / 100, accuracy: 0.01)
        // Пробная неделя (KAN-170) остаётся вводным предложением: новогоднее его не занимает.
        XCTAssertEqual(yearly.subscription?.introductoryOffer?.paymentMode, .freeTrial)
    }

    /// Погашение кода NEWYEAR2027 даёт годовую подписку по цене со скидкой.
    func testRedeemingCodeBuysYearlyWithDiscount() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        let products = try await Product.products(for: [NewYearOffer.productID])
        let yearly = try XCTUnwrap(products.first)

        let transaction = try await session.buyProduct(
            identifier: NewYearOffer.productID,
            options: [.codeOffer(referenceName: NewYearOffer.code)]
        )
        XCTAssertEqual(transaction.productID, NewYearOffer.productID)
        if #available(iOS 17.2, *) {
            XCTAssertEqual(transaction.offer?.type, .code)
        }
        let paid = try XCTUnwrap(transaction.price)
        let ratio = NSDecimalNumber(decimal: paid / yearly.price).doubleValue
        XCTAssertEqual(ratio, 1 - Double(NewYearOffer.discountPercent) / 100, accuracy: 0.01)

        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let entitlement) = result, entitlement.productID == NewYearOffer.productID {
                entitled = true
            }
        }
        XCTAssertTrue(entitled)
    }
}
