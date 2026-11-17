import SwiftUI

import StoreKit

/// Экран Pro с покупками через StoreKit 2. В сборке для SideStore покупки недоступны.
struct PaywallView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var shop = ProStore.shared
    @State private var selectedID = ProStore.yearlyID

    /// Функция, ради которой открыли экран: её показываем первой и выделяем.
    let highlight: ProFeature?

    @State private var trialEligible: Set<String> = []

    init(highlight: ProFeature? = nil) {
        self.highlight = highlight
    }

    private var features: [ProFeature] {
        guard let highlight else { return ProFeature.allCases }
        return [highlight] + ProFeature.allCases.filter { $0 != highlight }
    }

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
                            featureRow(feature, highlighted: feature == highlight)
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
            .task {
                await shop.loadProducts()
                await loadTrialEligibility()
            }
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
                        Text(buttonTitle)
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .glassButtonStyle(prominent: true)
            .disabled(shop.products.isEmpty || shop.isPurchasing)

            if let trialNote {
                Text(trialNote)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

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
                        Text("Free trial: \(Fmt.days(trialDays(offer.period)))")
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

    private func featureRow(_ feature: ProFeature, highlighted: Bool) -> some View {
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
                if highlighted {
                    Text("Available with Pro")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                    .padding(-10)
            }
        }
        .padding(.vertical, highlighted ? 6 : 0)
    }

    /// Пробный период выбранного плана, если он есть и пользователю ещё доступен.
    private var selectedTrialDays: Int? {
        guard let product = shop.products.first(where: { $0.id == selectedID }),
              trialEligible.contains(product.id),
              let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial
        else { return nil }
        return trialDays(offer.period)
    }

    private var buttonTitle: String {
        if selectedID == ProStore.lifetimeID { return String(localized: "Buy") }
        if selectedTrialDays != nil { return String(localized: "Start free trial") }
        return String(localized: "Subscribe")
    }

    private var trialNote: String? {
        guard let days = selectedTrialDays,
              let product = shop.products.first(where: { $0.id == selectedID }) else { return nil }
        return String(localized: "\(Fmt.days(days)) free, then \(priceText(product)). Cancel anytime.")
    }

    private func loadTrialEligibility() async {
        var eligible: Set<String> = []
        for product in shop.products {
            if let sub = product.subscription, sub.introductoryOffer?.paymentMode == .freeTrial,
               await sub.isEligibleForIntroOffer {
                eligible.insert(product.id)
            }
        }
        trialEligible = eligible
    }

    /// Длина пробного периода в днях (раньше месяц показывался как "1 день").
    private func trialDays(_ period: Product.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .day: period.value
        case .week: period.value * 7
        case .month: period.value * 30
        case .year: period.value * 365
        default: period.value
        }
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

/// Платные функции. Экран Pro открывается с той, на которую нажали.
enum ProFeature: String, CaseIterable, Identifiable {
    case unlimited, health, timer, mood, goals, reminders, quitMoney, pause, appLock, appIcons, csv, pets, looks

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .unlimited: "infinity"
        case .health: "heart.fill"
        case .timer: "timer"
        case .goals: "drop.fill"
        case .reminders: "bell.badge.fill"
        case .quitMoney: "banknote.fill"
        case .pause: "pause.circle.fill"
        case .mood: "face.smiling"
        case .appLock: "faceid"
        case .appIcons: "app.badge.fill"
        case .csv: "tablecells.fill"
        case .pets: "pawprint.fill"
        case .looks: "paintpalette.fill"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .unlimited: "Unlimited habits"
        case .health: "Apple Health"
        case .timer: "Timer on the Lock Screen"
        case .goals: "Daily goals"
        case .reminders: "Custom reminder repeats"
        case .quitMoney: "Money saved"
        case .pause: "Pause"
        case .mood: "Full mood journal"
        case .appLock: "Face ID lock"
        case .appIcons: "App icons"
        case .csv: "Export to CSV"
        case .pets: "Exclusive pets and more sparks"
        case .looks: "Exclusive avatars and backgrounds"
        }
    }

    var text: LocalizedStringKey {
        switch self {
        case .unlimited: "The free version has up to 5 active habits."
        case .health: "Habits check themselves off from steps, sleep, water, workouts and mindful minutes."
        case .timer: "A countdown on the Lock Screen and Dynamic Island that checks the habit off when time is up."
        case .goals: "Count glasses of water, pages or minutes toward a goal."
        case .reminders: "Choose how many times and how often each reminder repeats."
        case .quitMoney: "See how much money you save by quitting a habit."
        case .mood: "Your whole mood history, a monthly chart and which habits lift your mood."
        case .appLock: "Only you can open your habits and journal."
        case .appIcons: "Six new icons for your Home Screen."
        case .csv: "All your check-ins as a table for Numbers, Excel or Google Sheets."
        case .pause: "Take a break for a trip or illness without losing your streak."
        case .pets: "Dragon, unicorn and phoenix, a monthly gift of 100 sparks and a higher daily limit."
        case .looks: "Unlock the full collection and Pro-only designs."
        }
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
