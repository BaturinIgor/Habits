import Foundation

#if DEBUG
/// Демо-данные (названия привычек, групп, питомца, заметки) на языке интерфейса для макетов и
/// скриншотов App Store (KAN-236). Русский задаётся прямо в UITestSupport, здесь остальные языки.
/// Нет перевода — английский текст как есть.
enum DemoText {
    static func t(_ en: String) -> String {
        guard let language = Locale.preferredLanguages.first,
              let table = tables.first(where: { language.hasPrefix($0.key) })?.value else { return en }
        return table[en] ?? en
    }

    /// Язык для карточки «Изучение слов»: испанский, а для испаноговорящих — английский.
    static var wordsLanguage: String {
        Locale.preferredLanguages.first?.hasPrefix("es") == true ? "en" : "es"
    }

    private static let keys = [
        "Morning exercises", "At least 5 squats", "Drink water", "glasses", "Meditation",
        "Read 20 pages of a book before going to bed", "Gym", "Walk 10,000 steps", "No smoking",
        "Morning", "Family", "Anna", "Great workout", "Slept badly", "Dinner with friends", "Whiskers", "Ginger",
    ]

    private static func table(_ values: [String]) -> [String: String] {
        precondition(values.count == keys.count, "DemoText: \(values.count) of \(keys.count) strings")
        return Dictionary(uniqueKeysWithValues: zip(keys, values))
    }

    private static let tables: [String: [String: String]] = [
        "de": table(["Morgengymnastik", "Mindestens 5 Kniebeugen", "Wasser trinken", "Gläser", "Meditation",
                     "20 Seiten vor dem Schlafen lesen", "Fitnessstudio", "10.000 Schritte gehen", "Nicht rauchen",
                     "Morgen", "Familie", "Anna", "Tolles Training", "Schlecht geschlafen", "Essen mit Freunden",
                     "Minka", "Fuchsi"]),
        "es": table(["Ejercicio matutino", "Al menos 5 sentadillas", "Beber agua", "vasos", "Meditación",
                     "Leer 20 páginas antes de dormir", "Gimnasio", "Caminar 10.000 pasos", "No fumar",
                     "Mañana", "Familia", "Ana", "Gran entrenamiento", "Dormí mal", "Cena con amigos",
                     "Bigotes", "Canela"]),
        "fr": table(["Exercices du matin", "Au moins 5 squats", "Boire de l'eau", "verres", "Méditation",
                     "Lire 20 pages avant de dormir", "Salle de sport", "Marcher 10 000 pas", "Ne pas fumer",
                     "Matin", "Famille", "Anne", "Super séance", "Mal dormi", "Dîner entre amis",
                     "Moustache", "Roux"]),
        "hi": table(["सुबह का व्यायाम", "कम से कम 5 स्क्वैट", "पानी पिएँ", "गिलास", "ध्यान",
                     "सोने से पहले 20 पन्ने पढ़ें", "जिम", "10,000 कदम चलें", "धूम्रपान नहीं",
                     "सुबह", "परिवार", "अनन्या", "बढ़िया वर्कआउट", "नींद ठीक नहीं आई", "दोस्तों के साथ डिनर",
                     "मिनी", "भूरा"]),
        "id": table(["Olahraga pagi", "Minimal 5 squat", "Minum air", "gelas", "Meditasi",
                     "Baca 20 halaman sebelum tidur", "Gym", "Jalan 10.000 langkah", "Tidak merokok",
                     "Pagi", "Keluarga", "Ani", "Latihan mantap", "Kurang tidur", "Makan malam bersama teman",
                     "Mochi", "Jahe"]),
        "it": table(["Ginnastica mattutina", "Almeno 5 squat", "Bere acqua", "bicchieri", "Meditazione",
                     "Leggere 20 pagine prima di dormire", "Palestra", "Camminare 10.000 passi", "Non fumare",
                     "Mattina", "Famiglia", "Anna", "Allenamento ottimo", "Dormito male", "Cena con amici",
                     "Micio", "Rossino"]),
        "ja": table(["朝の運動", "スクワット5回だけでも", "水を飲む", "杯", "瞑想",
                     "寝る前に本を20ページ読む", "ジム", "1万歩歩く", "禁煙",
                     "朝", "家族", "ハナ", "最高のトレーニング", "よく眠れなかった", "友達と夕食",
                     "タマ", "コン"]),
        "ko": table(["아침 운동", "스쿼트 5번이라도", "물 마시기", "잔", "명상",
                     "자기 전 책 20쪽 읽기", "헬스장", "10,000보 걷기", "금연",
                     "아침", "가족", "지은", "최고의 운동", "잠을 설쳤다", "친구들과 저녁",
                     "나비", "노을"]),
        "pl": table(["Poranna gimnastyka", "Choć 5 przysiadów", "Pić wodę", "szklanek", "Medytacja",
                     "Przeczytać 20 stron przed snem", "Siłownia", "Przejść 10 000 kroków", "Nie palić",
                     "Poranek", "Rodzina", "Anna", "Świetny trening", "Słabo spałem", "Kolacja z przyjaciółmi",
                     "Mruczek", "Rudy"]),
        "pt": table(["Exercícios matinais", "Pelo menos 5 agachamentos", "Beber água", "copos", "Meditação",
                     "Ler 20 páginas antes de dormir", "Academia", "Caminhar 10.000 passos", "Não fumar",
                     "Manhã", "Família", "Ana", "Ótimo treino", "Dormi mal", "Jantar com amigos",
                     "Bigode", "Canela"]),
        "tr": table(["Sabah egzersizi", "En az 5 squat", "Su iç", "bardak", "Meditasyon",
                     "Yatmadan önce 20 sayfa oku", "Spor salonu", "10.000 adım yürü", "Sigara yok",
                     "Sabah", "Aile", "Ayşe", "Harika antrenman", "Kötü uyudum", "Arkadaşlarla akşam yemeği",
                     "Pamuk", "Tarçın"]),
        "zh": table(["晨练", "至少做 5 个深蹲", "喝水", "杯", "冥想",
                     "睡前读 20 页书", "健身房", "步行一万步", "不吸烟",
                     "早晨", "家人", "小安", "训练很棒", "没睡好", "和朋友吃晚饭",
                     "咪咪", "橘子"]),
    ]
}
#endif
