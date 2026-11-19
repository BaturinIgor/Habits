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
    static func appStoreURL(campaign: ShareCampaign, providerToken: String = providerToken) -> URL {
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

/// QR-код: картинка, где один пиксель — один модуль (с полем в 1 модуль от CoreImage).
struct QRCode {
    let image: UIImage
    /// Сторона в модулях вместе с полем.
    let modules: Int

    private static let context = CIContext()

    init?(_ text: String) {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = Self.context.createCGImage(output, from: output.extent) else { return nil }
        image = UIImage(cgImage: cgImage)
        modules = cgImage.width
    }

    /// Размер модуля в пунктах, чтобы при рендере ×3 модуль был целым числом пикселей (без «рваных» модулей),
    /// а весь код занимал не больше `side` пунктов.
    func modulePoints(fitting side: CGFloat, renderScale: CGFloat = 3) -> CGFloat {
        let pixels = max(1, (side * renderScale / CGFloat(modules)).rounded(.down))
        return pixels / renderScale
    }
}

/// Низ карточки, которой делятся: название приложения и QR-код со ссылкой на App Store.
/// Ссылка нарисована прямо на картинке, потому что Instagram Stories и «Фото» текст не берут.
struct ShareCardFooter: View {
    let campaign: ShareCampaign
    /// Призыв под названием. Параметр нужен тестам, чтобы проверить подпись на всех языках.
    var scanText = String(localized: "Scan to get ZenHab")

    /// Ширина колонки с текстом на картинке (карточка 360 pt минус поля и QR-код).
    static func textColumnWidth(cardWidth: CGFloat = 360, campaign: ShareCampaign) -> CGFloat {
        let qrSide: CGFloat
        if let qr = QRCode(AppInfo.appStoreURL(campaign: campaign).absoluteString) {
            let module = qr.modulePoints(fitting: 88)
            qrSide = module * CGFloat(qr.modules) + module * 6
        } else {
            qrSide = 0
        }
        return cardWidth - 2 * 22 - 12 - qrSide
    }

    var body: some View {
        let qr = QRCode(AppInfo.appStoreURL(campaign: campaign).absoluteString)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                    Text(verbatim: "ZenHab")
                }
                .font(.subheadline.weight(.bold))
                // Призыв сканировать — только если код действительно нарисован.
                // Переносится по словам на 2-3 строки: по-русски фраза не влезает в одну строку рядом с кодом.
                if qr != nil {
                    WordWrapText(scanText)
                        .font(.caption)
                        .opacity(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(verbatim: "App Store")
                    .font(.caption2.weight(.semibold))
                    .opacity(0.7)
            }
            Spacer(minLength: 0)
            if let qr {
                let module = qr.modulePoints(fitting: 88)
                Image(uiImage: qr.image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: module * CGFloat(qr.modules), height: module * CGFloat(qr.modules))
                    // Поле вокруг кода по стандарту — 4 модуля: 1 уже есть в картинке, ещё 3 — белая подложка.
                    .padding(module * 3)
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
        guard var top = keyWindow()?.rootViewController else {
            assertionFailure("ShareSheet: no window to present from")
            return
        }
        while let presented = top.presentedViewController {
            top = presented
        }
        // Второе быстрое нажатие или нажатие во время закрытия: не показываем окно поверх окна.
        if top is UIActivityViewController || top.isBeingDismissed || top.isBeingPresented {
            return
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            let bounds = top.view.bounds
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: bounds.midX, y: bounds.maxY - 1, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }

    @MainActor
    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.filter { $0.activationState == .foregroundActive }
        for scene in active + scenes {
            if let window = scene.keyWindow ?? scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first {
                return window
            }
        }
        return nil
    }
}
