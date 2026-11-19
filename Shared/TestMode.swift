import Foundation

/// Режим автотестов интерфейса: приложение запускается с аргументом `-uitest`.
/// Только в отладочной сборке; в сборках для App Store и SideStore всегда выключен.
enum TestMode {
    #if DEBUG
    static let isUITest = ProcessInfo.processInfo.arguments.contains("-uitest")
    #else
    static let isUITest = false
    #endif

    static func has(_ argument: String) -> Bool {
        isUITest && ProcessInfo.processInfo.arguments.contains(argument)
    }
}
