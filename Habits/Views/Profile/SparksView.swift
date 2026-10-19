import SwiftUI

/// Искры: баланс, откуда взялись, на что потратить.
struct SparksView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var notEnough = false
    @State private var showingPet = false

    var body: some View {
        let economy = store.economy
        let r = economy.report
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 6) {
                        SparkBadge(amount: economy.balance, font: .system(size: 44, weight: .bold, design: .rounded))
                        Text("Earned in total: \(r.total)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section("Earned") {
                    row("Check-ins", r.checks)
                    row("Perfect days", r.perfectDays)
                    row("Streaks", r.streaks)
                    row("Comebacks", r.comebacks)
                    row("Achievements", r.achievements)
                    if r.gifts > 0 { row("Pro gifts", r.gifts) }
                }

                Section {
                    Button {
                        withAnimation { if !store.buyFreeze() { notEnough = true } }
                    } label: {
                        HStack {
                            Label("Extra freeze", systemImage: "snowflake")
                                .foregroundStyle(Color.primary)
                            Spacer()
                            SparkBadge(amount: Sparks.freezePrice)
                        }
                    }
                    .disabled(store.extraFreezesThisMonth >= Sparks.maxExtraFreezes)
                    Button {
                        showingPet = true
                    } label: {
                        Label(store.data.wallet.pet == nil ? String(localized: "Get a pet") : String(localized: "Feed your pet"),
                              systemImage: "pawprint.fill")
                    }
                } header: {
                    Text("Spend")
                } footer: {
                    Text("Extra freezes this month: \(store.extraFreezesThisMonth)/\(Sparks.maxExtraFreezes). Avatars and backgrounds for sparks are in your profile.")
                }

                Section {
                    tip("checkmark.circle.fill", "1 spark for each check-in, up to \(Sparks.dailyCap) a day")
                    tip("checkmark.seal.fill", "+\(Sparks.perfectDayBonus) for a perfect day")
                    tip("flame.fill", "+\(Sparks.weekStreakBonus) for every 7 days of a streak, +\(Sparks.monthStreakBonus) for every 30")
                    tip("arrow.uturn.up.circle.fill", "+\(Sparks.comebackBonus) for coming back after a miss")
                    tip("trophy.fill", "+\(Sparks.achievementBonus) for each achievement")
                    tip("crown.fill", "Pro: +\(Sparks.proMonthlyGift) every month and up to \(Sparks.proDailyCap) a day")
                } header: {
                    Text("How to earn")
                } footer: {
                    Text("Only check-ins made the same day or the next one count. Unchecking a habit takes its spark back.")
                }
            }
            .appBackground()
            .navigationTitle("Sparks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingPet) { PetView() }
            .alert("Not enough sparks", isPresented: $notEnough) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check off habits to earn more.")
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: Int) -> some View {
        LabeledContent {
            SparkBadge(amount: value, font: .body.weight(.semibold))
        } label: {
            Text(title)
        }
    }

    private func tip(_ icon: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: icon).foregroundStyle(.orange)
        }
    }
}
