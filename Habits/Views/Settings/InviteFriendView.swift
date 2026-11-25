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
/// Условия продления стоят сразу под кодом, до кнопки: друг видит их до того, как ему отправят ссылку (3.1.2).
struct InviteFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var shop = ProStore.shared
    @State private var copied = false

    /// Цена месячной подписки, на которую действует код, например «149 ₽ в месяц».
    private var monthlyPrice: String? {
        shop.products.first(where: { $0.id == ProStore.monthlyID })
            .map { String(localized: "\($0.displayPrice) / month") }
    }

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

                    VStack(spacing: 10) {
                        codeCard
                        terms
                    }

                    ShareLink(item: FriendInvite.redeemURL,
                              message: Text("I track my habits with ZenHab. Try it: a month of Pro is free with this link: \(FriendInvite.redeemURL.absoluteString)")) {
                        // При крупном шрифте без иконки: иначе подпись переносится, а иконка висит у первой строки.
                        Group {
                            if typeSize.isAccessibilitySize {
                                Text("Send invite")
                            } else {
                                Label("Send invite", systemImage: "square.and.arrow.up")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("invite.send")
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
            .task { await shop.loadProducts() }
        }
    }

    private var terms: some View {
        VStack(spacing: 4) {
            if let monthlyPrice {
                Text("After the free month: \(monthlyPrice). Cancel anytime.")
            } else {
                Text("After the free month the subscription renews automatically. Cancel anytime.")
            }
            Text("The code won't work if your friend already has Pro.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .accessibilityIdentifier("invite.terms")
    }

    private var codeCard: some View {
        VStack(spacing: 12) {
            Text(FriendInvite.code)
                .font(.system(.title, design: .monospaced).weight(.bold))
                .tracking(2)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
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
            .accessibilityIdentifier("invite.copy")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
