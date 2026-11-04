import SwiftUI

/// Покупка за искры, которую нужно подтвердить.
struct SparkPurchase: Identifiable {
    let id = UUID()
    /// Что покупаем, например "Лиса" или "Заморозка".
    let title: String
    let price: Int
    let action: () -> Void
}

extension View {
    /// Подтверждение покупки за искры. Если искр не хватает, показывает, сколько ещё нужно.
    func sparkPurchaseAlert(_ purchase: Binding<SparkPurchase?>) -> some View {
        modifier(SparkPurchaseAlert(purchase: purchase))
    }
}

private struct SparkPurchaseAlert: ViewModifier {
    @Environment(HabitStore.self) private var store
    @Binding var purchase: SparkPurchase?

    func body(content: Content) -> some View {
        let balance = store.economy.balance
        let enough = (purchase?.price ?? 0) <= balance
        content.alert(
            enough ? Text("Buy for sparks?") : Text("Not enough sparks"),
            isPresented: Binding(get: { purchase != nil }, set: { if !$0 { purchase = nil } }),
            presenting: purchase
        ) { item in
            if item.price <= balance {
                Button("Buy") { withAnimation(.snappy) { item.action() } }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { item in
            if item.price <= balance {
                Text("\(item.title) costs \(item.price) sparks. You have \(balance).")
            } else {
                Text("\(item.title) costs \(item.price) sparks, you have \(balance). You need \(item.price - balance) more. Check off habits to earn them.")
            }
        }
    }
}
