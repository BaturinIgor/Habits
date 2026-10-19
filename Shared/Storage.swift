import Foundation

/// Общий контейнер приложения и виджета.
enum AppGroup {
    static let defaultIdentifier = "group.com.personal.habits"

    /// SideStore и AltStore при переподписи меняют идентификатор группы
    /// и записывают настоящий в Info.plist под ключом ALTAppGroups.
    private static var candidates: [String] {
        var result: [String] = []
        if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            result += groups
        }
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "appex" {
            let appURL = bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            if let groups = Bundle(url: appURL)?.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
                result += groups
            }
        }
        // Настоящие группы из профиля подписи (SideStore может переименовать группу
        // и не записать ALTAppGroups).
        result += provisionedGroups(in: bundleURL)
        if bundleURL.pathExtension == "appex" {
            result += provisionedGroups(in: bundleURL.deletingLastPathComponent().deletingLastPathComponent())
        }
        // Варианты с суффиксом команды, который SideStore добавляет к идентификаторам.
        for id in [Bundle.main.bundleIdentifier, appBundleIdentifier].compactMap({ $0 }) {
            if let range = id.range(of: "com.personal.habits.") {
                let suffix = id[range.upperBound...].split(separator: ".").last.map(String.init) ?? ""
                if !suffix.isEmpty && suffix != "widget" {
                    result.append("\(defaultIdentifier).\(suffix)")
                }
            }
        }
        result.append(defaultIdentifier)
        return result
    }

    private static var appBundleIdentifier: String? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "appex" else { return Bundle.main.bundleIdentifier }
        return Bundle(url: url.deletingLastPathComponent().deletingLastPathComponent())?.bundleIdentifier
    }

    /// Группы из embedded.mobileprovision: плист внутри подписанного файла.
    private static func provisionedGroups(in bundle: URL) -> [String] {
        guard let raw = try? Data(contentsOf: bundle.appendingPathComponent("embedded.mobileprovision")),
              let start = raw.range(of: Data("<?xml".utf8)),
              let end = raw.range(of: Data("</plist>".utf8), in: start.lowerBound..<raw.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: raw[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String] else { return [] }
        return groups.filter { !$0.contains("*") }
    }

    /// Для диагностики: какие группы пробовали и какие доступны.
    static var diagnostics: String {
        let fm = FileManager.default
        var seen = Set<String>()
        let list = candidates.filter { seen.insert($0).inserted }.map { id in
            (fm.containerURL(forSecurityApplicationGroupIdentifier: id) != nil ? "✓ " : "✗ ") + id
        }
        let own = (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String]).map { "\($0.count)" } ?? "-"
        return list.joined(separator: "\n") + "\nALTAppGroups: " + own + " · " + (Bundle.main.bundleIdentifier ?? "?")
    }

    /// Идентификатор группы, которая реально доступна, или nil, если общего контейнера нет
    /// (тогда приложение и виджет не видят данные друг друга).
    static let resolvedIdentifier: String? = candidates.first {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
    }

    /// Считается один раз за запуск: поиск группы читает файлы подписи.
    static let containerURL: URL = {
        let fm = FileManager.default
        for id in candidates {
            if let url = fm.containerURL(forSecurityApplicationGroupIdentifier: id) {
                return url
            }
        }
        let fallback = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }()
}

/// Отметка о том, что виджет смог прочитать общий контейнер (для проверки в настройках).
enum WidgetHeartbeat {
    private static var url: URL { AppGroup.containerURL.appendingPathComponent("widget-heartbeat") }

    static func write(habitCount: Int) {
        guard AppGroup.resolvedIdentifier != nil else { return }
        let text = "\(Date().timeIntervalSince1970)|\(habitCount)"
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    /// Когда виджет последний раз обновлялся и сколько привычек видел.
    static func read() -> (date: Date, habits: Int)? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let parts = text.split(separator: "|")
        guard parts.count == 2, let t = Double(parts[0]), let n = Int(parts[1]) else { return nil }
        return (Date(timeIntervalSince1970: t), n)
    }
}

/// Чтение и запись всех данных в один JSON-файл.
enum DataFile {
    private static let fileName = "habits-data.json"

    static var url: URL {
        AppGroup.containerURL.appendingPathComponent(fileName)
    }

    /// Возвращает nil, если файл есть, но прочитать его сейчас нельзя
    /// (например, телефон ещё не разблокирован после перезагрузки).
    /// Если раньше общей папки не было, данные лежали в папке приложения.
    /// Когда общая папка появилась, переносим их туда (только из приложения, не из виджета).
    private static func migrateFromPrivateFolderIfNeeded() {
        guard Bundle.main.bundleURL.pathExtension != "appex", AppGroup.resolvedIdentifier != nil else { return }
        let fm = FileManager.default
        let shared = url
        guard !fm.fileExists(atPath: shared.path) else { return }
        let privateDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let files = ["habits-data.json", "custom-background.jpg", "custom-avatar.jpg"]
        for name in files {
            let from = privateDir.appendingPathComponent(name)
            let to = shared.deletingLastPathComponent().appendingPathComponent(name)
            if fm.fileExists(atPath: from.path) && !fm.fileExists(atPath: to.path) {
                try? fm.copyItem(at: from, to: to)
            }
        }
    }

    static func loadIfAvailable() -> AppData? {
        migrateFromPrivateFolderIfNeeded()
        let url = self.url
        guard FileManager.default.fileExists(atPath: url.path) else { return AppData() }
        let raw: Data
        do {
            raw = try Data(contentsOf: url)
        } catch {
            return nil
        }
        do {
            return try JSONDecoder().decode(AppData.self, from: raw)
        } catch {
            // Виджет файл не трогает: возможно, его записала более новая версия приложения.
            if Bundle.main.bundleURL.pathExtension == "appex" { return nil }
            // Сохраняем повреждённый файл, чтобы данные можно было восстановить.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("habits-data-broken-\(stamp).json")
            // Переносим файл, а не копируем: так копия делается один раз,
            // а не при каждом чтении виджетом.
            if (try? FileManager.default.moveItem(at: url, to: backup)) == nil {
                try? raw.write(to: backup)
                try? FileManager.default.removeItem(at: url)
            }
            return AppData()
        }
    }

    static func load() -> AppData {
        loadIfAvailable() ?? AppData()
    }

    static func save(_ data: AppData) {
        do {
            let raw = try JSONEncoder().encode(data)
            let url = self.url
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try raw.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("Failed to save data: \(error)")
        }
    }
}
