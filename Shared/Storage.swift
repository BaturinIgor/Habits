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
    static var resolvedIdentifier: String? {
        candidates.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
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
