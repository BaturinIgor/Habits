import Foundation
import StoreKit

/// Новогоднее предложение (KAN-124, KAN-125): скидка на первый год Pro по коду предложения App Store.
///
/// Механика без своего сервера: в App Store Connect у годовой подписки заведён offer code с custom code
/// (`code`), человек погашает его в системном окне App Store прямо из приложения. Вводный период группы
/// занят пробной неделей (KAN-170), а promotional offer требует подписи ключом In-App Purchase на сервере.
///
/// Цену со скидкой до погашения кода StoreKit не отдаёт. Поэтому в App Store Connect заводится ещё и
/// promotional offer с теми же условиями (`priceOfferID`): его цену StoreKit показывает без подписи,
/// а покупать по нему приложение не пытается. Нет такого предложения — показываем только «−50%».
///
/// Даты, код и идентификаторы — только здесь: владелец правит их перед акцией.
enum NewYearOffer {
    /// Первый и последний день акции включительно, по местному времени человека.
    static let firstDay = DateComponents(year: 2026, month: 12, day: 20)
    static let lastDay = DateComponents(year: 2027, month: 1, day: 10)
    /// Скидка на первый год, в процентах. Должна совпадать с ценой предложения в App Store Connect.
    static let discountPercent = 50
    /// Custom code из App Store Connect: Subscriptions → Pro Yearly → Offer Codes.
    static let code = "NEWYEAR2027"
    /// Подписка, на которую действует код: годовая Pro (`ProStore.yearlyID`, его же меняет set_bundle_id.sh).
    static let productID = "com.personal.habits.pro.yearly"
    /// Promotional offer с теми же условиями: только чтобы взять цену со скидкой из StoreKit.
    static let priceOfferID = "newyear2027"

    /// Дни акции: с начала первого дня до конца последнего.
    static func interval(calendar: Calendar = .app) -> DateInterval? {
        guard let start = calendar.date(from: firstDay),
              let last = calendar.date(from: lastDay),
              let end = calendar.date(byAdding: .day, value: 1, to: last),
              start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Показывать ли предложение: только в дни акции и только без Pro.
    static func isAvailable(now: Date = Date(), isPro: Bool, calendar: Calendar = .app) -> Bool {
        guard !isPro, let interval = interval(calendar: calendar) else { return false }
        return now >= interval.start && now < interval.end
    }

    /// То же для экранов. В макетах и автотестах `-uitest-offer` включает акцию в любой день.
    static func isShown(isPro: Bool) -> Bool {
        #if SIDELOAD
        // В сборке для SideStore покупок и кодов App Store нет.
        return false
        #else
        if TestMode.has("-uitest-offer") { return !isPro }
        return isAvailable(isPro: isPro)
        #endif
    }

    /// Последний день акции для подписи «До 10 января».
    static var lastDayText: String {
        guard let last = Calendar.app.date(from: lastDay) else { return "" }
        return Fmt.dayMonthNoYear(last)
    }

    /// Цена первого года со скидкой из StoreKit (promotional offer с теми же условиями), если он заведён.
    static func discountedPrice(of product: Product) -> String? {
        product.subscription?.promotionalOffers.first { $0.id == priceOfferID }?.displayPrice
    }
}
