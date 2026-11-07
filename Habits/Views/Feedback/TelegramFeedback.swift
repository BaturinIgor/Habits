import Foundation
import UIKit

/// Отправка отзыва напрямую в Telegram-бот, без почты пользователя.
/// Токен бота и chat_id подставляются в Info.plist при сборке из секретов GitHub
/// (tools/feedback/inject_secrets.sh). Если их нет, форма работает через почту.
enum TelegramFeedback {
    enum Failure: Error { case notConfigured, badResponse }

    private static func value(_ key: String) -> String {
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var token: String { value("FeedbackBotToken") }
    static var chatID: String { value("FeedbackChatID") }
    static var isConfigured: Bool { !token.isEmpty && !chatID.isEmpty }

    /// Отправляет текст и, если есть, скриншот. Бросает ошибку, если Telegram не принял сообщение.
    static func send(text: String, screenshot: Data?) async throws {
        guard isConfigured else { throw Failure.notConfigured }
        // Лимит Telegram на одно сообщение 4096 символов.
        let clipped = text.count > 4000 ? String(text.prefix(4000)) + "…" : text
        try await call("sendMessage", json: ["chat_id": chatID, "text": clipped])
        if let screenshot, let jpeg = compressed(screenshot) {
            try await sendPhoto(jpeg)
        }
    }

    private static func endpoint(_ method: String) -> URL? {
        URL(string: "https://api.telegram.org/bot\(token)/\(method)")
    }

    private static func call(_ method: String, json: [String: String]) async throws {
        guard let url = endpoint(method) else { throw Failure.badResponse }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        try await perform(request)
    }

    private static func sendPhoto(_ jpeg: Data) async throws {
        guard let url = endpoint("sendPhoto") else { throw Failure.badResponse }
        let boundary = "zenhab-\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n\(chatID)\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"screenshot.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpeg)
        append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        try await perform(request)
    }

    private static func perform(_ request: URLRequest) async throws {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["ok"] as? Bool == true
        else { throw Failure.badResponse }
    }

    /// Telegram принимает фото до 10 МБ и сам уменьшает их, поэтому ограничиваем сторону 2048 px.
    private static func compressed(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 2048
        let side = max(image.size.width, image.size.height)
        guard side > maxSide else { return image.jpegData(compressionQuality: 0.8) }
        let scale = maxSide / side
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
