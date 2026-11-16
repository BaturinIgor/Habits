import AppIntents
import SwiftUI

/// Что нового в версии: показывается один раз после обновления.
struct WhatsNewView: View {
    /// Меняется, когда появляются новые карточки.
    static let version = "1.4"

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

                    if CloudBackup.isAvailable {
                        card(
                            icon: "icloud.fill",
                            color: .blue,
                            title: "Automatic iCloud backup",
                            text: "Your habits and history are saved to your iCloud by themselves. On a new iPhone, ZenHab offers to bring everything back."
                        ) {
                            NavigationLink {
                                BackupSettingsView()
                            } label: {
                                Text("Open backup")
                            }
                        }
                    }

                    card(
                        icon: "nosign",
                        color: .red,
                        title: "Quit a bad habit",
                        text: "Turn on “I'm quitting this habit” in a habit to see how many days you've been without it, your record and next milestone. With Pro, also the money saved."
                    ) {
                        Button("Try it", action: onTryVoice)
                    }

                    card(
                        icon: "flame.fill",
                        color: .orange,
                        title: "Bring back a streak",
                        text: "Missed a day and the streak broke? The next day you can bring it back for sparks."
                    ) {
                        EmptyView()
                    }

                    if FamilySync.isAvailable {
                        card(
                            icon: "person.2.fill",
                            color: .pink,
                            title: "Faster family groups",
                            text: "Changes from your family now show up within seconds while the app is open. Pull down on Today to update right away."
                        ) {
                            EmptyView()
                        }
                    }

                    if #available(iOS 18.0, *) {
                        card(
                            icon: "switch.2",
                            color: .green,
                            title: "Control Center",
                            text: "Add a habit button to Control Center, the Lock Screen or the Action button and check it off in one tap."
                        ) {
                            EmptyView()
                        }
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
