import Observation
import StoreKit

/// Покупки Pro через StoreKit 2: подписки на месяц и год и разовая покупка навсегда.
/// В сборке для SideStore (флаг SIDELOAD) покупки не работают, там Pro включается тестовым переключателем.
@MainActor
@Observable
final class ProStore {
    static let shared = ProStore()

    static let yearlyID = "com.personal.habits.pro.yearly"
    static let monthlyID = "com.personal.habits.pro.monthly"
    static let lifetimeID = "com.personal.habits.pro.lifetime"
    static let productIDs = [yearlyID, monthlyID, lifetimeID]

    var products: [Product] = []
    var isLoading = false
    var isPurchasing = false
    var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        guard products.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = Self.productIDs.compactMap { id in loaded.first { $0.id == id } }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Проверяет активные покупки и записывает результат в настройки (их читает и виджет).
    func refreshEntitlements() async {
        #if SIDELOAD
        return
        #else
        // В автотестах Pro включён демо-данными, а покупок в симуляторе нет.
        if TestMode.isUITest { return }
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        if HabitStore.shared.data.settings.proUnlocked != active {
            HabitStore.shared.setPro(active)
        }
        #endif
    }

    /// Возвращает true, если покупка прошла.
    @discardableResult
    func purchase(_ product: Product, source: String = "unknown") async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        let analytics = Analytics.shared
        analytics.send(.purchaseStarted(product: product.id, source: source))
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = String(localized: "The purchase could not be verified.")
                    analytics.send(.purchaseFailed(product: product.id, source: source))
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                analytics.send(.purchaseCompleted(product: product.id, source: source))
                return true
            case .pending, .userCancelled:
                analytics.send(.purchaseCancelled(product: product.id, source: source))
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            analytics.send(.purchaseFailed(product: product.id, source: source))
            return false
        }
    }

    func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshEntitlements()
        Analytics.shared.send(.restoreFinished(found: HabitStore.shared.data.isPro))
        if !HabitStore.shared.data.isPro {
            errorMessage = String(localized: "No purchases found for this Apple Account.")
        }
    }
}
