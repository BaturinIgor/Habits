import AppIntents
import SwiftUI

/// Что нового в версии: показывается один раз после обновления.
struct WhatsNewView: View {
    /// Меняется, когда появляются новые карточки.
    static let version = "1.3"

    /// Открыть окно новой привычки, чтобы попробовать голосовой ввод.
    let onTryVoice: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("What's new")
                        .font(.largeTitle.weight(.bold))
                        .padding(.bottom, 4)

                    if FamilySync.isAvailable {
                        card(
                            icon: "person.2.fill",
                            color: .pink,
                            title: "Family groups",
                            text: "Share a group with your family, for example “Dog” or “Home”. Everyone sees the same habits, checks them off and gets reminders."
                        ) {
                            NavigationLink {
                                GroupsView()
                            } label: {
                                Text("Open groups")
                            }
                        }
                    }

                    card(
                        icon: "mic.fill",
                        color: .orange,
                        title: "Create habits by voice",
                        text: "Tap the microphone in a new habit and say, for example: “Dog pills once a month on the 15th at 9 am”."
                    ) {
                        Button("Try it", action: onTryVoice)
                    }

                    card(
                        icon: "waveform",
                        color: .purple,
                        title: "Siri",
                        text: "Say “Check off a habit in ZenHab”, “Add a habit in ZenHab” or “What's left in ZenHab”."
                    ) {
                        ShortcutsLink()
                            .shortcutsLinkStyle(.automaticOutline)
                    }

                    card(
                        icon: "calendar",
                        color: .blue,
                        title: "New schedules",
                        text: "Every other day, every N days, once a month and once a year: for pills, bills and birthdays."
                    ) {
                        EmptyView()
                    }

                    card(
                        icon: "square.grid.2x2.fill",
                        color: .green,
                        title: "Groups on the Today screen and in the widget",
                        text: "Sort the Today screen by groups in Settings, and hold the Today widget to show one group."
                    ) {
                        EmptyView()
                    }
                }
                .padding(20)
            }
            .appBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
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
