import AppIntents
import SwiftUI

/// Что нового в версии: показывается один раз после обновления.
struct WhatsNewView: View {
    /// Меняется, когда появляются новые карточки.
    static let version = "1.6"

    /// Открыть окно новой привычки, чтобы попробовать новое.
    let onTryVoice: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("What's new")
                        .font(.largeTitle.weight(.bold))
                        .padding(.bottom, 4)

                    card(
                        icon: "applewatch",
                        color: .indigo,
                        title: "ZenHab on Apple Watch",
                        text: "See today's habits on your wrist and check them off with one tap. Everything syncs with your iPhone. Install ZenHab from the Watch app on your iPhone if it hasn't appeared on your watch."
                    ) {
                        EmptyView()
                    }

                    card(
                        icon: "watch.analog",
                        color: .green,
                        title: "Watch face complications",
                        text: "Add ZenHab to your watch face or Smart Stack to see how many habits are done today."
                    ) {
                        EmptyView()
                    }

                    card(
                        icon: "timer",
                        color: .orange,
                        title: "Timer on your wrist",
                        text: "With Pro, start a habit timer on Apple Watch. When time is up, the watch taps your wrist and checks the habit off."
                    ) {
                        EmptyView()
                    }
                }
                .padding(20)
                .uiTestScreen("whatsnew")
            }
            .appBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("sheet.close")
                }
            }
        }
    }

    private func card<Action: View>(
        icon: String,
        color: Color,
        title: LocalizedStringKey,
        text: LocalizedStringKey,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.gradient))
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                action()
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.background.secondary))
    }
}
