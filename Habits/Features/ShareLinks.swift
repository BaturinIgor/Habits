import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Откуда поделились приложением. Метка `ct` в ссылке на App Store: в App Store Connect
/// (Analytics → Campaigns) видно, какая карточка приводит установки.
enum ShareCampaign: String {
    case weekly = "share_weekly"
    case month = "share_month"
    case year = "share_year"
    case group = "share_group"
    case achievement = "share_achievement"
}

extension AppInfo {
    /// Provider token из App Store Connect (Analytics → Campaigns → Generate Campaign Link, параметр `pt`).
    /// Без него Apple не засчитывает метку `ct`, поэтому пока он пустой, ссылка идёт без меток:
    /// так QR-код короче и читается легче.
    static let providerToken = ""

    /// Ссылка на приложение в App Store для карточек «поделиться».
    static func appStoreURL(campaign: ShareCampaign) -> URL {
        var components = URLComponents(string: "https://apps.apple.com/app/id\(appStoreID)")!
        if !providerToken.isEmpty {
            components.queryItems = [
                URLQueryItem(name: "pt", value: providerToken),
                URLQueryItem(name: "ct", value: campaign.rawValue),
                URLQueryItem(name: "mt", value: "8"),
            ]
        }
        return components.url!
    }
}

enum QRCode {
    /// Чёрный QR-код на белом. Рисовать с `.interpolation(.none)`, чтобы края модулей оставались чёткими.
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Низ карточки, которой делятся: название приложения и QR-код со ссылкой на App Store.
/// Ссылка нарисована прямо на картинке, потому что Instagram Stories и «Фото» текст не берут.
struct ShareCardFooter: View {
    let campaign: ShareCampaign

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                    Text(verbatim: "ZenHab")
                }
                .font(.subheadline.weight(.bold))
                Text("Scan to get ZenHab")
                    .font(.caption)
                    .opacity(0.85)
                Text(verbatim: "App Store")
                    .font(.caption2.weight(.semibold))
                    .opacity(0.7)
            }
            Spacer(minLength: 0)
            if let qr = QRCode.image(for: AppInfo.appStoreURL(campaign: campaign).absoluteString) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 68, height: 68)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white))
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Окно «Поделиться» с картинкой и ссылкой сразу. ShareLink умеет делиться только элементами
/// одного типа. Telegram, iMessage и WhatsApp возьмут и картинку, и текст со ссылкой;
/// приложения, которые текст не принимают, возьмут только картинку с QR-кодом.
enum ShareSheet {
    @MainActor
    static func present(image file: URL, campaign: ShareCampaign) {
        present([file, message(campaign: campaign)])
    }

    static func message(campaign: ShareCampaign) -> String {
        String(localized: "Track your habits with ZenHab") + " " + AppInfo.appStoreURL(campaign: campaign).absoluteString
    }

    @MainActor
    private static func present(_ items: [Any]) {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        guard var top = window?.rootViewController else { return }
        while let presented = top.presentedViewController {
            top = presented
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = top.view
        top.present(controller, animated: true)
    }
}
