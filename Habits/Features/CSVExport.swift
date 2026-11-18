import Foundation

/// Выгрузка отметок в CSV (Pro): одна строка на привычку и день.
enum CSVExport {
    static func make(from data: AppData) -> String {
        let habits = Dictionary(uniqueKeysWithValues: data.habits.map { ($0.id, $0) })
        let groups = Dictionary(uniqueKeysWithValues: data.groups.map { ($0.id, $0.name) })
        var rows: [(day: String, order: Int, line: String)] = []
        for (key, checkIn) in data.checkIns {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let id = UUID(uuidString: parts[0]), let habit = habits[id] else { continue }
            let day = parts[1]
            let status: String
            switch checkIn.status {
            case .done: status = checkIn.isMinimum == true ? String(localized: "Minimum") : String(localized: "Done")
            case .skipped: status = String(localized: "Skipped")
            case nil: status = ""
            }
            // Пустые отметки (только сброшенный счётчик) не выгружаем.
            if status.isEmpty && (checkIn.count ?? 0) == 0 && (checkIn.note ?? "").isEmpty { continue }
            let target = habit.dailyTarget(isPro: true)
            let fields = [
                day,
                habit.name,
                habit.groupID.flatMap { groups[$0] } ?? "",
                status,
                target > 1 ? String(data.count(of: habit, day: day)) : "",
                target > 1 ? String(target) : "",
                habit.unit ?? "",
                data.moods[day].map { String($0.level) } ?? "",
                checkIn.note ?? "",
            ]
            rows.append((day, habit.sortOrder, fields.map(escape).joined(separator: ",")))
        }
        rows.sort { $0.day != $1.day ? $0.day < $1.day : $0.order < $1.order }
        let header = [
            String(localized: "Date"), String(localized: "Habit"), String(localized: "Group"),
            String(localized: "Status"), String(localized: "Count"), String(localized: "Goal"),
            String(localized: "Unit"), String(localized: "Mood (1-5)"), String(localized: "Note"),
        ].map(escape).joined(separator: ",")
        return ([header] + rows.map(\.line)).joined(separator: "\r\n") + "\r\n"
    }

    /// Файл во временной папке. BOM в начале нужен, чтобы Excel понял кириллицу.
    static func writeFile(from data: AppData) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zenhab-\(DayKey.make(Date())).csv")
        let text = "\u{FEFF}" + make(from: data)
        return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }

    static func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
