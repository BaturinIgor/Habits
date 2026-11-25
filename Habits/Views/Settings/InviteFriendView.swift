import SwiftUI
import UIKit

/// «Пригласи друга» (KAN-228): многоразовый код предложения на месяц Pro для новых подписчиков.
/// Сервера нет, поэтому награды пригласившему нет: только подарок другу. Код и предложение
/// заводятся в App Store Connect (`tools/appstore/asc_offers.py`).
enum FriendInvite {
    /// Custom offer code на месяц Pro (месячная подписка, бесплатно, только новые подписчики).
    static let code = "FRIEND2027"

    /// Ссылка Apple на активацию кода: открывает App Store с уже введённым кодом.
    static var redeemURL: URL {
        var components = URLComponents(string: "https://apps.apple.com/redeem")!
        components.queryItems = [
            URLQueryItem(name: "ctx", value: "offercodes"),
            URLQueryItem(name: "id", value: AppInfo.appStoreID),
            URLQueryItem(name: "code", value: code),
        ]
        return components.url!
    }
}

/// Строка в Настройках, раздел «Обратная связь».
struct InviteFriendRow: View {
    var onOpen: () -> Void

    var body: some View {
        // Как соседние «Написать разработчику» и «Оценить приложение»: цвет акцента.
        Button(action: onOpen) {
            Label("Invite a friend", systemImage: "heart.fill")
        }
        .accessibilityIdentifier("invite.settings")
    }
}

/// Шит с кодом и кнопкой «Отправить приглашение».
struct InviteFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 96, height: 96)
                        .background(Circle().fill(LinearGradient(colors: [.pink, .orange],
                                                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .accessibilityHidden(true)
                        .padding(.top, 8)

                    VStack(spacing: 10) {
                        Text("Give a friend a month of Pro")
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text("Your friend gets ZenHab Pro free for a month with this code. Each Apple ID can use it once.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    codeCard

                    ShareLink(item: FriendInvite.redeemURL,
                              message: Text("I track my habits with ZenHab. Try it: a month of Pro is free with this link: \(FriendInvite.redeemURL.absoluteString)")) {
                        Label("Send invite", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .accessibilityIdentifier("invite.send")

                    Text("After the free month the subscription renews at the regular price unless cancelled. It doesn't work if your friend already has Pro.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("Invite a friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var codeCard: some View {
        VStack(spacing: 12) {
            Text(FriendInvite.code)
                .font(.system(.title, design: .monospaced).weight(.bold))
                .tracking(2)
                .textSelection(.enabled)
            Button {
                UIPasteboard.general.string = FriendInvite.code
                withAnimation { copied = true }
            } label: {
                Label(copied ? String(localized: "Code copied") : String(localized: "Copy code"),
                      systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.pink)
            .accessibilityIdentifier("invite.copy")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.pink.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
    }
}
