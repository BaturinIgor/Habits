import SwiftUI

import StoreKit

/// Экран Pro с покупками через StoreKit 2. В сборке для SideStore покупки недоступны.
struct PaywallView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var shop = ProStore.shared
    @State private var selectedID = ProStore.yearlyID

    private struct Feature: Identifiable {
        let icon: String
        let title: LocalizedStringKey
        let text: LocalizedStringKey
        var id: String { icon }
    }

    private let features: [Feature] = [
        Feature(icon: "infinity", title: "Unlimited habits",
                text: "The free version has up to 5 active habits."),
        Feature(icon: "bell.badge.fill", title: "Custom reminder repeats",
                text: "Choose how many times and how often each reminder repeats."),
        Feature(icon: "drop.fill", title: "Daily goals",
                text: "Count glasses of water, pages or minutes toward a goal."),
        Feature(icon: "pause.circle.fill", title: "Pause",
                text: "Take a break for a trip or illness without losing your streak."),
        Feature(icon: "pawprint.fill", title: "Exclusive pets and more sparks",
                text: "Dragon, unicorn and phoenix, a monthly gift of 100 sparks and a higher daily limit."),
        Feature(icon: "paintpalette.fill", title: "Exclusive avatars and backgrounds",
                text: "Unlock the full collection and Pro-only designs."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(Circle().fill(LinearGradient(
                            colors: [Color(red: 1, green: 0.62, blue: 0.26), Color(red: 0.92, green: 0.23, blue: 0.35)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )))
                        .shadow(color: .orange.opacity(0.35), radius: 18, y: 8)
                        .padding(.top, 12)

                    VStack(spacing: 6) {
                        Text("Habit Tracker Pro")
                            .font(.largeTitle.weight(.bold))
                        Text("More freedom for the habits that matter.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(features) { feature in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: feature.icon)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.accentColor.gradient))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(feature.title)
                                        .font(.headline)
                                    Text(feature.text)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 18, cornerRadius: 24)

                    if store.data.isPro {
                        Label("Pro is active", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                    } else {
                        purchaseSection
                    }
                }
                .padding(20)
            }
            .background(AppBackground())
            .task { await shop.loadProducts() }
            .alert(
                "Purchase failed",
                isPresented: Binding(get: { shop.errorMessage != nil }, set: { if !$0 { shop.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(shop.errorMessage ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }
}

extension PaywallView {
    @ViewBuilder
    var purchaseSection: some View {
        #if SIDELOAD
        Text("Purchases work only in the App Store version. In this build, Pro can be turned on for testing in Settings.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        #else
        VStack(spacing: 12) {
            if shop.products.isEmpty {
                ProgressView()
                    .frame(height: 120)
            } else {
                ForEach(shop.products, id: \.id) { product in
                    planRow(product)
                }
            }

            Button {
                guard let product = shop.products.first(where: { $0.id == selectedID }) else { return }
                Task {
                    if await shop.purchase(product) { dismiss() }
                }
            } label: {
                Group {
                    if shop.isPurchasing {
                        ProgressView()
                    } else {
                        Text(selectedID == ProStore.lifetimeID ? String(localized: "Buy") : String(localized: "Subscribe"))
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .disabled(shop.products.isEmpty || shop.isPurchasing)

            Text("Subscriptions renew automatically until cancelled. Cancel anytime in Settings, Apple Account, Subscriptions, at least 24 hours before the period ends.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Restore purchases") {
                    Task { await shop.restore() }
                }
                Button("Terms of Use") { openURL(AppInfo.termsURL) }
                Button("Privacy Policy") { openURL(AppInfo.privacyURL) }
            }
            .font(.caption.weight(.medium))
            .disabled(shop.isPurchasing)
        }
        #endif
    }

    private func planRow(_ product: Product) -> some View {
        let isSelected = product.id == selectedID
        return Button {
            selectedID = product.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(planTitle(product)).font(.headline)
                        if product.id == ProStore.yearlyID, let saving = yearlySaving {
                            Text(verbatim: "-\(saving)%")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(.green))
                        }
                    }
                    if let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial {
                        Text("Free trial: \(Fmt.days(offer.period.value * (offer.period.unit == .week ? 7 : 1)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(priceText(product))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.primary)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.background.opacity(0.7))
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func planTitle(_ product: Product) -> String {
        switch product.id {
        case ProStore.yearlyID: String(localized: "Yearly")
        case ProStore.monthlyID: String(localized: "Monthly")
        default: String(localized: "Forever")
        }
    }

    private func priceText(_ product: Product) -> String {
        switch product.id {
        case ProStore.yearlyID: String(localized: "\(product.displayPrice) / year")
        case ProStore.monthlyID: String(localized: "\(product.displayPrice) / month")
        default: product.displayPrice
        }
    }

    private var yearlySaving: Int? {
        guard let year = shop.products.first(where: { $0.id == ProStore.yearlyID }),
              let month = shop.products.first(where: { $0.id == ProStore.monthlyID }),
              month.price > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: year.price / (month.price * 12)).doubleValue
        let saving = Int(((1 - ratio) * 100).rounded())
        return saving > 0 ? saving : nil
    }
}

/// Небольшая метка "PRO" рядом с платными функциями.
struct ProBadge: View {
    var body: some View {
        Text(verbatim: "PRO")
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(LinearGradient(
                colors: [Color(red: 1, green: 0.62, blue: 0.26), Color(red: 0.92, green: 0.23, blue: 0.35)],
                startPoint: .leading, endPoint: .trailing
            )))
    }
}
