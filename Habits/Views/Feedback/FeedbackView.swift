import MessageUI
import StoreKit
import SwiftUI
import UIKit

/// Настройки обратной связи. Адрес задаётся здесь один раз.
enum AppInfo {
    static let supportEmail = "zdrgvretrsyhtrse@mail.ru"
    /// Числовой Apple ID приложения из App Store Connect, появится после создания карточки.
    static let appStoreID = ""
    static let privacyURL = URL(string: "https://baturinigor.github.io/Habits/privacy.html")!
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static var reviewURL: URL? {
        appStoreID.isEmpty ? nil : URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

/// Форма обратной связи: тип сообщения, текст и техническая информация.
struct FeedbackView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    enum Kind: String, CaseIterable, Identifiable {
        case bug, idea, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .bug: String(localized: "Report a bug")
            case .idea: String(localized: "Suggest an idea")
            case .other: String(localized: "Other")
            }
        }
        var icon: String {
            switch self {
            case .bug: "ladybug.fill"
            case .idea: "lightbulb.fill"
            case .other: "bubble.left.fill"
            }
        }
    }

    @State var kind: Kind = .bug
    @State private var message = ""
    @State private var includeDiagnostics = true
    @State private var showingMail = false
    @State private var showingNoMail = false
    @State private var sent = false
    @FocusState private var focused: Bool

    private var subject: String {
        "\(String(localized: "Habit Tracker")): \(kind.title)"
    }

    private var diagnostics: String {
        let device = UIDevice.current
        let language = Locale.preferredLanguages.first ?? "?"
        return """
        App: \(AppInfo.version)
        iOS: \(device.systemVersion)
        Device: \(Self.modelIdentifier)
        Language: \(language)
        Habits: \(store.data.activeHabits.count)
        Pro: \(store.data.isPro ? "yes" : "no")
        """
    }

    private var body_: String {
        var text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if includeDiagnostics { text += "\n\n---\n" + diagnostics }
        return text
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Topic", selection: $kind) {
                        ForEach(Kind.allCases) { kind in
                            Label(kind.title, systemImage: kind.icon).tag(kind)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    TextField(kind == .bug ? String(localized: "What happened and what did you expect?") : String(localized: "Tell us what you think"),
                              text: $message, axis: .vertical)
                        .lineLimit(5...12)
                        .focused($focused)
                } footer: {
                    if kind == .bug {
                        Text("Steps to reproduce help a lot. You can attach a screenshot in the email.")
                    }
                }

                Section {
                    Toggle("Include technical info", isOn: $includeDiagnostics)
                } footer: {
                    Text("App version, iOS version, device model and language. Your habits and notes are never sent.")
                }

                Section {
                    Button {
                        send()
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .appBackground()
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        focused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                }
            }
            .sheet(isPresented: $showingMail, onDismiss: { if sent { dismiss() } }) {
                MailComposer(recipient: AppInfo.supportEmail, subject: subject, body: body_) { result in
                    sent = result == .sent || result == .saved
                }
                .ignoresSafeArea()
            }
            .alert("No mail account", isPresented: $showingNoMail) {
                Button("Copy address") {
                    UIPasteboard.general.string = AppInfo.supportEmail
                }
                Button("Copy message") {
                    UIPasteboard.general.string = body_
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Set up Mail on this iPhone or send your message to \(AppInfo.supportEmail).")
            }
        }
    }

    private func send() {
        focused = false
        if MFMailComposeViewController.canSendMail() {
            showingMail = true
            return
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = AppInfo.supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body_)]
        if let url = components.url {
            openURL(url) { accepted in
                if accepted { dismiss() } else { showingNoMail = true }
            }
        } else {
            showingNoMail = true
        }
    }

    private static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// Обёртка над системным окном письма.
struct MailComposer: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let onFinish: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void
        init(onFinish: @escaping (MFMailComposeResult) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result)
            controller.dismiss(animated: true)
        }
    }
}

/// Просьба оценить приложение: не раньше 7 дней использования и 20 отметок,
/// не чаще раза в 120 дней. Система сама решает, показывать ли окно.
enum RatingPrompt {
    private static let lastKey = "ratingPromptLast"

    @MainActor
    static func maybeAsk(data: AppData, requestReview: RequestReviewAction) {
        let defaults = UserDefaults.standard
        let firstUse = data.habits.map(\.createdAt).min() ?? Date()
        let done = data.checkIns.values.filter { $0.status == .done }.count
        guard Date().timeIntervalSince(firstUse) > 7 * 86400, done >= 20 else { return }
        if let last = defaults.object(forKey: lastKey) as? Date, Date().timeIntervalSince(last) < 120 * 86400 { return }
        defaults.set(Date(), forKey: lastKey)
        requestReview()
    }
}
