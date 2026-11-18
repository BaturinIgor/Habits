import LocalAuthentication
import SwiftUI
import UIKit

/// Блокировка приложения по Face ID или Touch ID (Pro). Экран блокировки живёт в отдельном окне
/// поверх всего, поэтому закрывает и открытые листы.
@MainActor
final class AppLock {
    static let shared = AppLock()

    private var window: UIWindow?
    private var authenticating = false

    /// Можно ли включить блокировку: на устройстве есть Face ID, Touch ID или хотя бы код-пароль.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Название способа разблокировки для подписей.
    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return String(localized: "passcode")
        }
    }

    static var methodSymbol: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "faceid"
        }
    }

    var isEnabled: Bool {
        #if DEBUG
        if TestMode.isUITest { return false }
        #endif
        let data = HabitStore.shared.data
        return data.isPro && data.settings.appLock
    }

    var isLocked: Bool { window != nil }

    /// Закрывает приложение экраном блокировки, если она включена.
    func lock() {
        guard isEnabled, window == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState != .unattached }) else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        let host = UIHostingController(rootView: LockScreenView {
            Task { await AppLock.shared.unlockIfNeeded() }
        }
        .environment(HabitStore.shared))
        host.view.backgroundColor = .systemBackground
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
    }

    /// Спрашивает Face ID и убирает экран блокировки при успехе.
    func unlockIfNeeded() async {
        guard window != nil, !authenticating else { return }
        // Блокировку выключили (например, закончился Pro): просто открываем.
        guard isEnabled else { removeWindow(); return }
        authenticating = true
        let ok = await Self.authenticate(reason: String(localized: "Unlock ZenHab"))
        authenticating = false
        if ok { removeWindow() }
    }

    private func removeWindow() {
        window?.isHidden = true
        window = nil
    }

    /// Проверка владельца: Face ID или Touch ID, а если не вышло, код-пароль iPhone.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel")
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

/// Что видно, пока приложение закрыто.
struct LockScreenView: View {
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image("IconPreview-Original")
                .resizable()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("ZenHab is locked")
                .font(.title2.weight(.semibold))
            Spacer()
            Button(action: unlock) {
                Label("Unlock", systemImage: AppLock.methodSymbol)
                    .font(.headline)
                    .frame(maxWidth: 260)
                    .padding(.vertical, 6)
            }
            .glassButtonStyle(prominent: true)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground())
    }
}
