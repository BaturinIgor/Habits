import StoreKit
import SwiftUI
import UIKit

/// Новогоднее предложение (KAN-125): карточка на «Сегодня», строка в настройках и блок на экране Pro.
/// Когда и кому показывать, решает `NewYearOffer.isShown`.

private let offerGradient = LinearGradient(
    colors: [Color(red: 0.93, green: 0.22, blue: 0.33), Color(red: 0.98, green: 0.55, blue: 0.2)],
    startPoint: .topLeading, endPoint: .bottomTrailing
)

/// «50%» по правилам языка («50 %» во французском и немецком).
private var offerPercent: String {
    (Double(NewYearOffer.discountPercent) / 100).formatted(.percent.precision(.fractionLength(0)))
}

/// Метка «−50%».
struct NewYearOfferBadge: View {
    var body: some View {
        Text(verbatim: "−\(offerPercent)")
            .font(.caption.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(offerGradient))
    }
}

/// Карточка на «Сегодня»: открывает экран Pro со скидкой, крестик прячет её до конца акции.
struct NewYearOfferBanner: View {
    var onOpen: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "gift.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(offerGradient))
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        WordWrapText(String(localized: "New Year offer"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                        NewYearOfferBadge()
                    }
                    WordWrapText(String(localized: "First year of Pro \(offerPercent) off") + " · "
                        + String(localized: "Until \(NewYearOffer.lastDayText)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("offer.banner")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.red.opacity(0.10))
        }
    }
}

/// Строка в настройках под «Трекер привычек Pro».
struct NewYearOfferRow: View {
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            LabeledContent {
                NewYearOfferBadge()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New Year offer").foregroundStyle(Color.primary)
                        Text("Until \(NewYearOffer.lastDayText)")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                } icon: {
                    Image(systemName: "gift.fill").foregroundStyle(.red)
                }
            }
        }
        .accessibilityIdentifier("offer.settings")
    }
}

/// Блок со скидкой на экране Pro (`PaywallView(source: .newYearOffer)`).
/// Зачёркнутая цена — обычная цена года из StoreKit, цена со скидкой — из promotional offer
/// с теми же условиями (см. `NewYearOffer`). Покупка — погашением кода в окне App Store.
struct NewYearOfferCard: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Годовая подписка из StoreKit; пока не загрузилась — без цен.
    let product: Product?
    @State private var redeeming = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "gift.fill")
                    .foregroundStyle(offerGradient)
                Text("New Year offer")
                    .font(.headline)
                Spacer()
                NewYearOfferBadge()
            }

            Text("First year of Pro \(offerPercent) off")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if let product {
                prices(product)
            }

            Text("Until \(NewYearOffer.lastDayText)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Button {
                copyCode()
                redeeming = true
            } label: {
                Text("Get the discount")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .glassButtonStyle(prominent: true)
            .accessibilityIdentifier("offer.redeem")

            HStack(spacing: 8) {
                Text("Code: \(NewYearOffer.code)")
                    .font(.subheadline.weight(.semibold).monospaced())
                    .textSelection(.enabled)
                Button {
                    copyCode()
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel(Text("Copy code"))
            }

            Text("Tap the button and paste the code in the App Store window. You'll see the final price before you pay.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("After the first year, Pro renews at the regular price. Cancel anytime.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .card(padding: 18, cornerRadius: 24)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(offerGradient, lineWidth: 2)
        }
        .offerCodeRedemption(isPresented: $redeeming) { result in
            guard case .success = result else { return }
            Task { await redeemed() }
        }
    }

    /// Обычная цена зачёркнута, рядом цена первого года со скидкой, если StoreKit её знает.
    @ViewBuilder
    private func prices(_ product: Product) -> some View {
        let regular = String(localized: "\(product.displayPrice) / year")
        if let discounted = NewYearOffer.discountedPrice(of: product) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: regular)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(verbatim: regular))
                Text("\(discounted) for the first year")
                    .font(.headline)
            }
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("offer.prices")
        } else {
            Text(verbatim: regular)
                .font(.subheadline)
                .strikethrough()
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("offer.prices")
        }
    }

    private func copyCode() {
        UIPasteboard.general.string = NewYearOffer.code
        withAnimation { copied = true }
    }

    /// Код погашен: проверяем покупки, отмечаем покупку в аналитике и закрываем экран.
    private func redeemed() async {
        await ProStore.shared.refreshEntitlements()
        guard store.data.isPro else { return }
        Analytics.shared.send(.purchaseCompleted(product: NewYearOffer.productID, source: PaywallSource.newYearOffer.rawValue))
        dismiss()
    }
}
