import AVFoundation
import Foundation

// MARK: - Языки словаря

/// Языки, на которых есть каждое слово словаря. Совпадают с языками интерфейса.
enum WordLanguage {
    /// Порядок колонок в words.tsv после категории.
    static let codes = ["en", "ru", "de", "fr", "es", "pt-BR", "it", "tr", "pl", "id", "zh-Hans", "ja", "ko", "hi"]

    /// Язык интерфейса, на котором показываем перевод.
    static var interface: String {
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        if codes.contains(preferred) { return preferred }
        let base = preferred.split(separator: "-").first.map(String.init) ?? preferred
        return codes.first { $0.hasPrefix(base) } ?? "en"
    }

    /// Название языка на языке интерфейса, с заглавной буквы.
    static func name(_ code: String) -> String {
        let locale = Locale(identifier: interface)
        let base = code.split(separator: "-").first.map(String.init) ?? code
        let name = locale.localizedString(forLanguageCode: base) ?? code
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }

    /// Название для названия привычки: в русском и похожих языках со строчной буквы.
    static func inlineName(_ code: String) -> String {
        let locale = Locale(identifier: interface)
        let base = code.split(separator: "-").first.map(String.init) ?? code
        return locale.localizedString(forLanguageCode: base) ?? code
    }

    /// Название привычки по умолчанию, например "Учить испанский".
    static func habitName(_ code: String) -> String {
        String(localized: "Learn \(inlineName(code))")
    }

    /// Язык, который предложить первым: английский, а если интерфейс английский, то испанский.
    static var suggested: String { interface == "en" ? "es" : "en" }

    /// Языки, которые можно учить: все, кроме языка интерфейса.
    static var learnable: [String] { codes.filter { $0 != interface } }

    /// Голос для озвучки.
    static func voiceCode(_ code: String) -> String {
        switch code {
        case "en": return "en-US"
        case "ru": return "ru-RU"
        case "de": return "de-DE"
        case "fr": return "fr-FR"
        case "es": return "es-ES"
        case "pt-BR": return "pt-BR"
        case "it": return "it-IT"
        case "tr": return "tr-TR"
        case "pl": return "pl-PL"
        case "id": return "id-ID"
        case "zh-Hans": return "zh-CN"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "hi": return "hi-IN"
        default: return code
        }
    }
}

// MARK: - Словарь

struct Word: Identifiable, Hashable {
    /// Английское слово, оно же постоянный ключ прогресса.
    let id: String
    let category: String
    let forms: [String: String]

    func text(_ language: String) -> String { forms[language] ?? id }
}

enum WordBank {
    /// Все слова из words.tsv в порядке изучения: от простых к сложным.
    static let all: [Word] = load()

    private static func load() -> [Word] {
        guard let url = Bundle.main.url(forResource: "words", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var result: [Word] = []
        var seen = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == WordLanguage.codes.count + 1, !parts[0].hasPrefix("#") else { continue }
            let id = parts[1]
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            var forms: [String: String] = [:]
            for (index, code) in WordLanguage.codes.enumerated() {
                forms[code] = parts[index + 1]
            }
            result.append(Word(id: id, category: parts[0], forms: forms))
        }
        return result
    }
}

// MARK: - Интервальное повторение

enum WordPlan {
    /// Через сколько дней повторить слово из коробки.
    static func interval(box: Int) -> Int {
        switch box {
        case ...1: return 1
        case 2: return 3
        case 3: return 7
        case 4: return 14
        case 5: return 30
        default: return 60
        }
    }

    /// Слово считается выученным с этой коробки.
    static let learnedBox = 4

    static let perDayOptions = [5, 10, 15, 20]

    static func key(_ language: String, _ wordID: String) -> String { language + "|" + wordID }

    /// Слова на сегодня: сначала повторение, потом новые до дневной нормы.
    static func session(language: String, perDay: Int, data: AppData, day: String, extraNew: Int = 0) -> [Word] {
        var reviews: [(Word, String)] = []
        var newWords: [Word] = []
        var introducedToday = 0
        for word in WordBank.all {
            if let card = data.words[key(language, word.id)] {
                if card.introduced == day { introducedToday += 1 }
                if card.due <= day && card.lastSeen != day { reviews.append((word, card.due)) }
            } else {
                newWords.append(word)
            }
        }
        let reviewLimit = max(perDay * 2, 10)
        let due = reviews.sorted { $0.1 < $1.1 }.prefix(reviewLimit).map { $0.0 }
        let newCount = max(0, perDay + extraNew - introducedToday)
        return Array(due) + newWords.prefix(newCount)
    }

    struct Progress {
        var learned = 0
        var learning = 0
        var total = WordBank.all.count
    }

    static func progress(language: String, data: AppData) -> Progress {
        var result = Progress()
        let prefix = language + "|"
        for (key, card) in data.words where key.hasPrefix(prefix) {
            if card.box >= learnedBox { result.learned += 1 } else { result.learning += 1 }
        }
        return result
    }
}

extension AppData {
    /// Ответ на карточку: "знаю" поднимает слово в коробке, "ещё учу" возвращает в начало.
    mutating func answerWord(language: String, wordID: String, known: Bool, day: String, calendar: Calendar = .app) {
        let key = WordPlan.key(language, wordID)
        let isNew = words[key] == nil
        var card = words[key] ?? WordCard(box: 0, due: day, introduced: day, lastSeen: day)
        // Новое слово, которое уже знаешь, сразу уходит на повтор через несколько дней.
        card.box = known ? card.box + (isNew ? 2 : 1) : 1
        let today = DayKey.date(day, calendar: calendar) ?? Date()
        let next = calendar.date(byAdding: .day, value: WordPlan.interval(box: card.box), to: today) ?? today
        card.due = DayKey.make(next, calendar: calendar)
        card.lastSeen = day
        words[key] = card
    }
}

// MARK: - Озвучка

@MainActor
enum Speaker {
    private static let synthesizer = AVSpeechSynthesizer()

    static func say(_ text: String, language: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: WordLanguage.voiceCode(language))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }
}
