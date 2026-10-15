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
        result.append(defaultIdentifier)
        return result
    }

    static var containerURL: URL {
        let fm = FileManager.default
        for id in candidates {
            if let url = fm.containerURL(forSecurityApplicationGroupIdentifier: id) {
                return url
            }
        }
        let fallback = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
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
    static func loadIfAvailable() -> AppData? {
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
            // Сохраняем повреждённый файл, чтобы данные можно было восстановить.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("habits-data-broken-\(stamp).json")
            try? raw.write(to: backup)
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
            print("Не удалось сохранить данные: \(error)")
        }
    }
}
