import AppIntents
import SwiftUI

/// Что нового в версии: показывается один раз после обновления.
struct WhatsNewView: View {
    /// Меняется, когда появляются новые карточки.
    static let version = "1.7"

    /// Открыть окно новой привычки, чтобы попробовать новое.
    let onTryVoice: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        analyticsBody.analyticsScreen(.whatsNew)
    }

    @ViewBuilder private var analyticsBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("What's new")
                        .font(.largeTitle.weight(.bold))
                        .padding(.bottom, 4)

                    card(
                        icon: "clock.arrow.circlepath",
                        color: .blue,
                        title: "Smart reminder time",
                        text: "Turn on Smart time next to a reminder, and it moves closer to when you usually check the habit off. It's free for everyone."
                    ) {
                        EmptyView()
                    }

                    card(
                        icon: "mic.fill",
                        color: .pink,
                        title: "Siri and Shortcuts",
                        text: "Ask Siri to check off a habit, log your mood or tell you what's left today. With Pro, Siri also starts a habit timer. All actions are in the Shortcuts app."
                    ) {
                        EmptyView()
                    }

                    card(
                        icon: "face.smiling",
                        color: .orange,
                        title: "Mood insights",
                        text: "With Pro, the mood journal shows which habits go with your better days. Open it from Statistics or the mood card on Today."
                    ) {
                        EmptyView()
                    }

                    card(
                        icon: "textformat.size",
                        color: .green,
                        title: "Large text",
                        text: "Screens now fit the largest text sizes better, and VoiceOver reads more buttons clearly."
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
