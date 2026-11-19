import AppIntents
import SwiftUI

/// Что нового в версии: показывается один раз после обновления.
struct WhatsNewView: View {
    /// Меняется, когда появляются новые карточки.
    static let version = "1.5"

    /// Открыть окно новой привычки, чтобы попробовать новое.
    let onTryVoice: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingMood = false

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
                        icon: "face.smiling",
                        color: .orange,
                        title: "Mood journal",
                        text: "Rate your day with one tap at the bottom of Today and add a few words. With Pro, see your full history, a monthly chart and which habits lift your mood."
                    ) {
                        Button("Open journal") { showingMood = true }
                    }

                    card(
                        icon: "app.badge.fill",
                        color: .pink,
                        title: "New app icons",
                        text: "Sunset, Forest, Rose, Gold, Midnight and Light. Pick one in Settings with Pro."
                    ) {
                        NavigationLink {
                            AppIconView()
                        } label: {
                            Text("Choose an icon")
                        }
                    }

                    if AppLock.isAvailable {
                        card(
                            icon: AppLock.methodSymbol,
                            color: .green,
                            title: "Lock with Face ID",
                            text: "With Pro, ZenHab asks for Face ID or your passcode when you open it, so your habits and journal stay private. Turn it on in Settings."
                        ) {
                            EmptyView()
                        }
                    }

                    card(
                        icon: "tablecells.fill",
                        color: .teal,
                        title: "Export to CSV",
                        text: "With Pro, export all check-ins with notes and mood as a table for Numbers, Excel or Google Sheets."
                    ) {
                        NavigationLink {
                            BackupSettingsView()
                        } label: {
                            Text("Open export")
                        }
                    }

                    card(
                        icon: "crown.fill",
                        color: .yellow,
                        title: "Clearer Pro",
                        text: "The Pro screen now lists everything it includes, and opens on the feature you tapped."
                    ) {
                        EmptyView()
                    }
                }
                .padding(20)
                .uiTestScreen("whatsnew")
            }
            .appBackground()
            .sheet(isPresented: $showingMood) {
                MoodJournalView()
            }
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
