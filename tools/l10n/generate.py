import os, re, glob
SP = os.path.dirname(os.path.abspath(__file__)) + '/'
ROOT = os.path.abspath(os.path.join(SP, '..', '..')) + '/'
OUT = ROOT + 'Localization/'
LANGS = ['ru', 'de', 'fr', 'es', 'zh-Hans', 'ja', 'ko', 'hi']

rows = {}
for n, line in enumerate(open(SP + 'translations.txt', encoding='utf-8'), 1):
    line = line.rstrip('\n')
    if not line.strip():
        continue
    parts = line.split('||')
    assert len(parts) == 9, (n, len(parts), line[:60])
    assert parts[0] not in rows, ('dup', parts[0])
    rows[parts[0]] = parts[1:]

# Языки, добавленные позже: отдельный файл на язык, строки "ключ||перевод".
# Строка без перевода берётся из английского ключа, а скрипт её показывает.
EXTRA = ['pt-BR', 'it', 'tr', 'pl', 'id']
extra = {}
for lang in EXTRA:
    m = {}
    for n, line in enumerate(open(SP + 'extra/' + lang + '.txt', encoding='utf-8'), 1):
        line = line.rstrip('\n')
        if not line.strip():
            continue
        parts = line.split('||')
        assert len(parts) == 2, (lang, n, line[:60])
        assert parts[0] not in m, (lang, 'dup', parts[0])
        m[parts[0]] = parts[1]
    unknown = sorted(set(m) - set(rows))
    untranslated = sorted(set(rows) - set(m))
    if unknown or untranslated:
        print(lang, 'unknown keys:', unknown, 'untranslated:', untranslated)
    for k, v in m.items():
        # Плейсхолдеры должны совпадать с ключом.
        ph = lambda t: sorted(re.findall(r'%(?:\d\$)?(?:lld|@)', t.replace('%1$', '%').replace('%2$', '%')))
        assert ph(k) == ph(v), (lang, k, v)
    extra[lang] = m

# Plural forms: key -> {lang: {category: text}}
P = {
 '%lld days': {
  'en': {'one': '%lld day', 'other': '%lld days'},
  'ru': {'one': '%lld день', 'few': '%lld дня', 'many': '%lld дней', 'other': '%lld дня'},
  'de': {'one': '%lld Tag', 'other': '%lld Tage'},
  'fr': {'one': '%lld jour', 'other': '%lld jours'},
  'es': {'one': '%lld día', 'other': '%lld días'},
  'zh-Hans': {'other': '%lld 天'}, 'ja': {'other': '%lld日'}, 'ko': {'other': '%lld일'},
  'hi': {'one': '%lld दिन', 'other': '%lld दिन'},
 },
 '%lld habits left': {
  'en': {'one': '%lld habit left', 'other': '%lld habits left'},
  'ru': {'one': 'Осталась %lld привычка', 'few': 'Осталось %lld привычки', 'many': 'Осталось %lld привычек', 'other': 'Осталось %lld привычки'},
  'de': {'one': 'Noch %lld Gewohnheit', 'other': 'Noch %lld Gewohnheiten'},
  'fr': {'one': 'Encore %lld habitude', 'other': 'Encore %lld habitudes'},
  'es': {'one': 'Queda %lld hábito', 'other': 'Quedan %lld hábitos'},
  'zh-Hans': {'other': '还剩 %lld 个习惯'}, 'ja': {'other': '残り %lld 件'}, 'ko': {'other': '%lld개 남음'},
  'hi': {'one': '%lld आदत बाकी', 'other': '%lld आदतें बाकी'},
 },
 '%lld habits planned': {
  'en': {'one': '%lld habit planned', 'other': '%lld habits planned'},
  'ru': {'one': 'Запланирована %lld привычка', 'few': 'Запланировано %lld привычки', 'many': 'Запланировано %lld привычек', 'other': 'Запланировано %lld привычки'},
  'de': {'one': '%lld Gewohnheit geplant', 'other': '%lld Gewohnheiten geplant'},
  'fr': {'one': '%lld habitude prévue', 'other': '%lld habitudes prévues'},
  'es': {'one': '%lld hábito previsto', 'other': '%lld hábitos previstos'},
  'zh-Hans': {'other': '计划 %lld 个习惯'}, 'ja': {'other': '予定 %lld 件'}, 'ko': {'other': '%lld개 예정'},
  'hi': {'one': '%lld आदत तय', 'other': '%lld आदतें तय'},
 },
 '%lld repeats every %lld min': {
  'en': {'one': '%1$lld repeat every %2$lld min', 'other': '%1$lld repeats every %2$lld min'},
  'ru': {'one': '%1$lld повтор каждые %2$lld мин', 'few': '%1$lld повтора каждые %2$lld мин', 'many': '%1$lld повторов каждые %2$lld мин', 'other': '%1$lld повтора каждые %2$lld мин'},
  'de': {'one': '%1$lld Wiederholung alle %2$lld Min.', 'other': '%1$lld Wiederholungen alle %2$lld Min.'},
  'fr': {'one': '%1$lld rappel toutes les %2$lld min', 'other': '%1$lld rappels toutes les %2$lld min'},
  'es': {'one': '%1$lld repetición cada %2$lld min', 'other': '%1$lld repeticiones cada %2$lld min'},
  'zh-Hans': {'other': '每 %2$lld 分钟重复 %1$lld 次'}, 'ja': {'other': '%2$lld分ごとに%1$lld回'},
  'ko': {'other': '%2$lld분마다 %1$lld회'}, 'hi': {'one': 'हर %2$lld मिनट में %1$lld बार', 'other': 'हर %2$lld मिनट में %1$lld बार'},
 },

 '%lld weeks': {
  'en': {'one': '%lld week', 'other': '%lld weeks'},
  'ru': {'one': '%lld неделя', 'few': '%lld недели', 'many': '%lld недель', 'other': '%lld недели'},
  'de': {'one': '%lld Woche', 'other': '%lld Wochen'},
  'fr': {'one': '%lld semaine', 'other': '%lld semaines'},
  'es': {'one': '%lld semana', 'other': '%lld semanas'},
  'zh-Hans': {'other': '%lld 周'}, 'ja': {'other': '%lld週'}, 'ko': {'other': '%lld주'},
  'hi': {'one': '%lld हफ़्ता', 'other': '%lld हफ़्ते'},
 },
 '%lld times a week': {
  'en': {'one': '%lld time a week', 'other': '%lld times a week'},
  'ru': {'one': '%lld раз в неделю', 'few': '%lld раза в неделю', 'many': '%lld раз в неделю', 'other': '%lld раза в неделю'},
  'de': {'one': '%lld-mal pro Woche', 'other': '%lld-mal pro Woche'},
  'fr': {'one': '%lld fois par semaine', 'other': '%lld fois par semaine'},
  'es': {'one': '%lld vez por semana', 'other': '%lld veces por semana'},
  'zh-Hans': {'other': '每周 %lld 次'}, 'ja': {'other': '週%lld回'}, 'ko': {'other': '주 %lld회'},
  'hi': {'one': 'हफ़्ते में %lld बार', 'other': 'हफ़्ते में %lld बार'},
 },
}
# Множественные формы для языков из EXTRA.
P_EXTRA = {
 '%lld days': {
  'pt-BR': {'one': '%lld dia', 'other': '%lld dias'},
  'it': {'one': '%lld giorno', 'other': '%lld giorni'},
  'tr': {'one': '%lld gün', 'other': '%lld gün'},
  'pl': {'one': '%lld dzień', 'few': '%lld dni', 'many': '%lld dni', 'other': '%lld dnia'},
  'id': {'other': '%lld hari'},
 },
 '%lld habits left': {
  'pt-BR': {'one': 'Falta %lld hábito', 'other': 'Faltam %lld hábitos'},
  'it': {'one': 'Manca %lld abitudine', 'other': 'Mancano %lld abitudini'},
  'tr': {'one': '%lld alışkanlık kaldı', 'other': '%lld alışkanlık kaldı'},
  'pl': {'one': 'Został %lld nawyk', 'few': 'Zostały %lld nawyki', 'many': 'Zostało %lld nawyków', 'other': 'Zostało %lld nawyku'},
  'id': {'other': '%lld kebiasaan lagi'},
 },
 '%lld habits planned': {
  'pt-BR': {'one': '%lld hábito planejado', 'other': '%lld hábitos planejados'},
  'it': {'one': '%lld abitudine prevista', 'other': '%lld abitudini previste'},
  'tr': {'one': '%lld alışkanlık planlandı', 'other': '%lld alışkanlık planlandı'},
  'pl': {'one': 'Zaplanowano %lld nawyk', 'few': 'Zaplanowano %lld nawyki', 'many': 'Zaplanowano %lld nawyków', 'other': 'Zaplanowano %lld nawyku'},
  'id': {'other': '%lld kebiasaan direncanakan'},
 },
 '%lld repeats every %lld min': {
  'pt-BR': {'one': '%1$lld repetição a cada %2$lld min', 'other': '%1$lld repetições a cada %2$lld min'},
  'it': {'one': '%1$lld ripetizione ogni %2$lld min', 'other': '%1$lld ripetizioni ogni %2$lld min'},
  'tr': {'one': 'Her %2$lld dk %1$lld tekrar', 'other': 'Her %2$lld dk %1$lld tekrar'},
  'pl': {'one': '%1$lld powtórzenie co %2$lld min', 'few': '%1$lld powtórzenia co %2$lld min', 'many': '%1$lld powtórzeń co %2$lld min', 'other': '%1$lld powtórzenia co %2$lld min'},
  'id': {'other': '%1$lld kali setiap %2$lld menit'},
 },
 '%lld weeks': {
  'pt-BR': {'one': '%lld semana', 'other': '%lld semanas'},
  'it': {'one': '%lld settimana', 'other': '%lld settimane'},
  'tr': {'one': '%lld hafta', 'other': '%lld hafta'},
  'pl': {'one': '%lld tydzień', 'few': '%lld tygodnie', 'many': '%lld tygodni', 'other': '%lld tygodnia'},
  'id': {'other': '%lld minggu'},
 },
 '%lld times a week': {
  'pt-BR': {'one': '%lld vez por semana', 'other': '%lld vezes por semana'},
  'it': {'one': '%lld volta a settimana', 'other': '%lld volte a settimana'},
  'tr': {'one': 'Haftada %lld kez', 'other': 'Haftada %lld kez'},
  'pl': {'one': '%lld raz w tygodniu', 'few': '%lld razy w tygodniu', 'many': '%lld razy w tygodniu', 'other': '%lld razy w tygodniu'},
  'id': {'other': '%lld kali seminggu'},
 },
}
for key, forms in P_EXTRA.items():
    P[key].update(forms)

# Короткое название под иконкой. Внутри приложения используется полное: "Трекер привычек".
NAMES = {'en': 'ZenHab', 'ru': 'ZenHab', 'de': 'ZenHab', 'fr': 'ZenHab',
         'es': 'ZenHab', 'zh-Hans': 'ZenHab', 'ja': 'ZenHab', 'ko': 'ZenHab', 'hi': 'ZenHab',
         'pt-BR': 'ZenHab', 'it': 'ZenHab', 'tr': 'ZenHab', 'pl': 'ZenHab', 'id': 'ZenHab'}

# Тексты запросов доступа (Info.plist) для голосового ввода.
PERMISSIONS = {
 'NSMicrophoneUsageDescription': {
  'en': 'ZenHab uses the microphone so you can create a habit by voice.',
  'ru': 'ZenHab использует микрофон, чтобы создавать привычки голосом.',
  'de': 'ZenHab nutzt das Mikrofon, damit du Gewohnheiten per Sprache anlegen kannst.',
  'fr': 'ZenHab utilise le micro pour que tu puisses créer une habitude à la voix.',
  'es': 'ZenHab usa el micrófono para que puedas crear hábitos con la voz.',
  'zh-Hans': 'ZenHab 使用麦克风，让你可以用语音创建习惯。',
  'ja': 'ZenHabはマイクを使って、声で習慣を作成できるようにします。',
  'ko': 'ZenHab은 음성으로 습관을 만들 수 있도록 마이크를 사용합니다.',
  'hi': 'ZenHab माइक्रोफ़ोन का उपयोग करता है ताकि आप आवाज़ से आदत बना सकें।',
  'pt-BR': 'O ZenHab usa o microfone para você criar hábitos por voz.',
  'it': 'ZenHab usa il microfono per permetterti di creare abitudini con la voce.',
  'tr': 'ZenHab, sesle alışkanlık oluşturabilmeniz için mikrofonu kullanır.',
  'pl': 'ZenHab używa mikrofonu, aby można było tworzyć nawyki głosem.',
  'id': 'ZenHab menggunakan mikrofon agar Anda bisa membuat kebiasaan dengan suara.',
 },
 'NSSpeechRecognitionUsageDescription': {
  'en': 'ZenHab turns your words into a habit with a schedule and a reminder time.',
  'ru': 'ZenHab превращает твои слова в привычку с расписанием и временем напоминания.',
  'de': 'ZenHab macht aus deinen Worten eine Gewohnheit mit Zeitplan und Erinnerung.',
  'fr': 'ZenHab transforme tes mots en habitude avec un horaire et un rappel.',
  'es': 'ZenHab convierte tus palabras en un hábito con horario y recordatorio.',
  'zh-Hans': 'ZenHab 会把你说的话变成带有日程和提醒时间的习惯。',
  'ja': 'ZenHabは話した内容を、スケジュールとリマインダー付きの習慣にします。',
  'ko': 'ZenHab은 말한 내용을 일정과 알림 시간이 있는 습관으로 만듭니다.',
  'hi': 'ZenHab आपके शब्दों को समय-सारणी और रिमाइंडर वाली आदत में बदलता है।',
  'pt-BR': 'O ZenHab transforma suas palavras em um hábito com agenda e lembrete.',
  'it': 'ZenHab trasforma le tue parole in un\'abitudine con programma e promemoria.',
  'tr': 'ZenHab sözlerinizi programı ve hatırlatma saati olan bir alışkanlığa dönüştürür.',
  'pl': 'ZenHab zamienia Twoje słowa w nawyk z harmonogramem i przypomnieniem.',
  'id': 'ZenHab mengubah ucapan Anda menjadi kebiasaan dengan jadwal dan pengingat.',
 },
 'NSHealthShareUsageDescription': {
  'en': 'ZenHab reads steps, sleep, water, exercise and mindful minutes to check off linked habits for you.',
  'ru': 'ZenHab читает шаги, сон, воду, упражнения и минуты осознанности, чтобы сам отмечать связанные привычки.',
  'de': 'ZenHab liest Schritte, Schlaf, Wasser, Training und Achtsamkeitsminuten, um verknüpfte Gewohnheiten für dich abzuhaken.',
  'fr': 'ZenHab lit les pas, le sommeil, l\'eau, l\'exercice et la pleine conscience pour cocher tes habitudes liées.',
  'es': 'ZenHab lee pasos, sueño, agua, ejercicio y minutos de atención plena para marcar tus hábitos vinculados.',
  'zh-Hans': 'ZenHab 读取步数、睡眠、饮水、锻炼和正念分钟数，为你自动打卡关联的习惯。',
  'ja': 'ZenHabは歩数、睡眠、水分、エクササイズ、マインドフルネスを読み取り、連携した習慣を自動でチェックします。',
  'ko': 'ZenHab은 걸음 수, 수면, 물, 운동, 마음챙김 시간을 읽어 연결된 습관을 자동으로 체크합니다.',
  'hi': 'ZenHab कदम, नींद, पानी, व्यायाम और माइंडफ़ुल मिनट पढ़ता है ताकि जुड़ी आदतें अपने आप पूरी हों।',
  'pt-BR': 'O ZenHab lê passos, sono, água, exercício e atenção plena para marcar seus hábitos vinculados.',
  'it': 'ZenHab legge passi, sonno, acqua, esercizio e minuti di consapevolezza per spuntare le abitudini collegate.',
  'tr': 'ZenHab, bağlı alışkanlıkları işaretlemek için adım, uyku, su, egzersiz ve farkındalık dakikalarını okur.',
  'pl': 'ZenHab odczytuje kroki, sen, wodę, ćwiczenia i minuty uważności, aby odhaczać powiązane nawyki.',
  'id': 'ZenHab membaca langkah, tidur, air, olahraga, dan menit kesadaran untuk mencentang kebiasaan yang terhubung.',
 },
 # Apple требует этот ключ при правах HealthKit, хотя ZenHab в Здоровье ничего не записывает.
 'NSHealthUpdateUsageDescription': {
  'en': 'ZenHab does not write to Apple Health. It only reads data to check off linked habits.',
  'ru': 'ZenHab ничего не записывает в Здоровье. Он только читает данные, чтобы отмечать связанные привычки.',
  'de': 'ZenHab schreibt nichts in Apple Health. Es liest nur Daten, um verknüpfte Gewohnheiten abzuhaken.',
  'fr': 'ZenHab n\'écrit rien dans Santé. Il lit seulement des données pour cocher tes habitudes liées.',
  'es': 'ZenHab no escribe nada en Salud. Solo lee datos para marcar tus hábitos vinculados.',
  'zh-Hans': 'ZenHab 不会向“健康”写入任何数据，只读取数据来为关联的习惯打卡。',
  'ja': 'ZenHabはヘルスケアに何も書き込みません。連携した習慣をチェックするためにデータを読み取るだけです。',
  'ko': 'ZenHab은 건강 앱에 아무것도 기록하지 않습니다. 연결된 습관을 체크하기 위해 데이터를 읽기만 합니다.',
  'hi': 'ZenHab Apple Health में कुछ नहीं लिखता। यह जुड़ी आदतें पूरी करने के लिए केवल डेटा पढ़ता है।',
  'pt-BR': 'O ZenHab não grava nada no Saúde. Ele só lê dados para marcar seus hábitos vinculados.',
  'it': 'ZenHab non scrive nulla in Salute. Legge solo i dati per spuntare le abitudini collegate.',
  'tr': 'ZenHab Sağlık uygulamasına hiçbir şey yazmaz. Yalnızca bağlı alışkanlıkları işaretlemek için veri okur.',
  'pl': 'ZenHab niczego nie zapisuje w Zdrowiu. Tylko odczytuje dane, aby odhaczać powiązane nawyki.',
  'id': 'ZenHab tidak menulis apa pun ke Kesehatan. Aplikasi hanya membaca data untuk mencentang kebiasaan yang terhubung.',
 },
 # Блокировка приложения по Face ID (Pro, с версии 1.5).
 'NSFaceIDUsageDescription': {
  'en': 'ZenHab uses Face ID to lock the app so only you can see your habits and mood journal.',
  'ru': 'ZenHab использует Face ID, чтобы закрыть приложение и твои привычки и дневник настроения видел только ты.',
  'de': 'ZenHab nutzt Face ID, um die App zu sperren, damit nur du deine Gewohnheiten und dein Stimmungstagebuch siehst.',
  'fr': 'ZenHab utilise Face ID pour verrouiller l\'app afin que toi seul voies tes habitudes et ton journal d\'humeur.',
  'es': 'ZenHab usa Face ID para bloquear la app y que solo tú veas tus hábitos y tu diario de ánimo.',
  'zh-Hans': 'ZenHab 使用面容 ID 锁定应用，只有你能看到自己的习惯和心情日记。',
  'ja': 'ZenHabはFace IDでアプリをロックし、習慣と気分日記をあなただけが見られるようにします。',
  'ko': 'ZenHab은 Face ID로 앱을 잠가 습관과 기분 일기를 본인만 볼 수 있게 합니다.',
  'hi': 'ZenHab ऐप को लॉक करने के लिए Face ID का उपयोग करता है, ताकि आपकी आदतें और मूड डायरी सिर्फ़ आप देख सकें।',
  'pt-BR': 'O ZenHab usa o Face ID para bloquear o app, assim só você vê seus hábitos e seu diário de humor.',
  'it': 'ZenHab usa Face ID per bloccare l\'app, così solo tu vedi le tue abitudini e il diario dell\'umore.',
  'tr': 'ZenHab, alışkanlıklarını ve ruh hâli günlüğünü yalnızca senin görebilmen için uygulamayı Face ID ile kilitler.',
  'pl': 'ZenHab używa Face ID do blokowania aplikacji, aby tylko ty widział swoje nawyki i dziennik nastroju.',
  'id': 'ZenHab memakai Face ID untuk mengunci aplikasi agar hanya kamu yang melihat kebiasaan dan jurnal suasana hatimu.',
 },
}

# Фразы Siri из Habits/Features/SiriIntents.swift (HabitsShortcuts), в том же порядке.
SHORTCUT_KEYS = [
 'Check off ${habit} in ${applicationName}',
 'Mark ${habit} in ${applicationName}',
 'Check off a habit in ${applicationName}',
 'Add a habit in ${applicationName}',
 'Add a reminder in ${applicationName}',
 'New habit in ${applicationName}',
 "What's left in ${applicationName}",
 "What's left today in ${applicationName}",
]
SHORTCUTS = {
 'ru': ['Отметь ${habit} в ${applicationName}', 'Готово ${habit} в ${applicationName}', 'Отметь привычку в ${applicationName}',
        'Добавь привычку в ${applicationName}', 'Добавь напоминание в ${applicationName}', 'Новая привычка в ${applicationName}',
        'Что осталось в ${applicationName}', 'Что осталось на сегодня в ${applicationName}'],
 'de': ['Hake ${habit} in ${applicationName} ab', 'Markiere ${habit} in ${applicationName}', 'Hake eine Gewohnheit in ${applicationName} ab',
        'Füge eine Gewohnheit in ${applicationName} hinzu', 'Füge eine Erinnerung in ${applicationName} hinzu', 'Neue Gewohnheit in ${applicationName}',
        'Was ist offen in ${applicationName}', 'Was ist heute offen in ${applicationName}'],
 'fr': ['Coche ${habit} dans ${applicationName}', 'Marque ${habit} dans ${applicationName}', 'Coche une habitude dans ${applicationName}',
        'Ajoute une habitude dans ${applicationName}', 'Ajoute un rappel dans ${applicationName}', 'Nouvelle habitude dans ${applicationName}',
        "Qu'est-ce qui reste dans ${applicationName}", "Qu'est-ce qui reste aujourd'hui dans ${applicationName}"],
 'es': ['Marca ${habit} en ${applicationName}', 'Completa ${habit} en ${applicationName}', 'Marca un hábito en ${applicationName}',
        'Añade un hábito en ${applicationName}', 'Añade un recordatorio en ${applicationName}', 'Nuevo hábito en ${applicationName}',
        'Qué me queda en ${applicationName}', 'Qué me queda hoy en ${applicationName}'],
 'pt-BR': ['Marque ${habit} no ${applicationName}', 'Conclua ${habit} no ${applicationName}', 'Marque um hábito no ${applicationName}',
           'Adicione um hábito no ${applicationName}', 'Adicione um lembrete no ${applicationName}', 'Novo hábito no ${applicationName}',
           'O que falta no ${applicationName}', 'O que falta hoje no ${applicationName}'],
 'it': ['Spunta ${habit} in ${applicationName}', 'Segna ${habit} in ${applicationName}', "Spunta un'abitudine in ${applicationName}",
        "Aggiungi un'abitudine in ${applicationName}", 'Aggiungi un promemoria in ${applicationName}', 'Nuova abitudine in ${applicationName}',
        'Cosa resta in ${applicationName}', 'Cosa resta oggi in ${applicationName}'],
 'tr': ['${applicationName} içinde ${habit} işaretle', "${applicationName}'da ${habit} tamamla", '${applicationName} içinde alışkanlık işaretle',
        '${applicationName} içine alışkanlık ekle', '${applicationName} içine hatırlatma ekle', '${applicationName} yeni alışkanlık',
        "${applicationName}'da ne kaldı", "${applicationName}'da bugün ne kaldı"],
 'zh-Hans': ['在${applicationName}中打卡${habit}', '在${applicationName}中完成${habit}', '在${applicationName}中打卡习惯',
             '在${applicationName}中添加习惯', '在${applicationName}中添加提醒', '${applicationName}新习惯',
             '${applicationName}还剩什么', '${applicationName}今天还剩什么'],
 'ja': ['${applicationName}で${habit}をチェック', '${applicationName}で${habit}を完了', '${applicationName}で習慣をチェック',
        '${applicationName}で習慣を追加', '${applicationName}でリマインダーを追加', '${applicationName}で新しい習慣',
        '${applicationName}で残りは', '${applicationName}で今日の残りは'],
 'ko': ['${applicationName}에서 ${habit} 체크', '${applicationName}에서 ${habit} 완료', '${applicationName}에서 습관 체크',
        '${applicationName}에서 습관 추가', '${applicationName}에서 알림 추가', '${applicationName} 새 습관',
        '${applicationName}에서 뭐가 남았어', '${applicationName}에서 오늘 뭐가 남았어'],
}

# 1.7, KAN-136: настроение и таймер. Новые фразы дописываются в конец, в том же порядке, что в HabitsShortcuts.
SHORTCUT_KEYS += [
 'Log my mood in ${applicationName}',
 'Mood check-in in ${applicationName}',
 'Start a timer for ${habit} in ${applicationName}',
 'Start a habit timer in ${applicationName}',
]
for _lang, _phrases in {
 'ru': ['Запиши настроение в ${applicationName}', 'Отметь настроение в ${applicationName}',
        'Запусти таймер ${habit} в ${applicationName}', 'Запусти таймер привычки в ${applicationName}'],
 'de': ['Trage meine Stimmung in ${applicationName} ein', 'Stimmung in ${applicationName} eintragen',
        'Starte den Timer für ${habit} in ${applicationName}', 'Starte einen Gewohnheits-Timer in ${applicationName}'],
 'fr': ['Note mon humeur dans ${applicationName}', 'Mon humeur dans ${applicationName}',
        'Lance le minuteur pour ${habit} dans ${applicationName}', "Lance un minuteur d'habitude dans ${applicationName}"],
 'es': ['Registra mi ánimo en ${applicationName}', 'Mi ánimo en ${applicationName}',
        'Inicia el temporizador de ${habit} en ${applicationName}', 'Inicia un temporizador de hábito en ${applicationName}'],
 'pt-BR': ['Registre meu humor no ${applicationName}', 'Meu humor no ${applicationName}',
           'Inicie o timer de ${habit} no ${applicationName}', 'Inicie um timer de hábito no ${applicationName}'],
 'it': ['Registra il mio umore in ${applicationName}', 'Il mio umore in ${applicationName}',
        'Avvia il timer per ${habit} in ${applicationName}', 'Avvia un timer abitudine in ${applicationName}'],
 'tr': ['${applicationName} içinde ruh hâlimi kaydet', '${applicationName} ruh hâli kaydı',
        '${applicationName} içinde ${habit} zamanlayıcısını başlat', '${applicationName} içinde alışkanlık zamanlayıcısı başlat'],
 'zh-Hans': ['在${applicationName}中记录心情', '${applicationName}心情打卡',
             '在${applicationName}中开始${habit}计时', '在${applicationName}中开始习惯计时'],
 'ja': ['${applicationName}で気分を記録', '${applicationName}で気分チェック',
        '${applicationName}で${habit}のタイマーを開始', '${applicationName}で習慣タイマーを開始'],
 'ko': ['${applicationName}에서 기분 기록', '${applicationName} 기분 체크',
        '${applicationName}에서 ${habit} 타이머 시작', '${applicationName}에서 습관 타이머 시작'],
}.items():
    SHORTCUTS[_lang] += _phrases
# Хинди, польский и индонезийский: раньше фраз не было, теперь все 14 языков.
SHORTCUTS.update({
 'hi': ['${applicationName} में ${habit} पूरी करें', '${applicationName} में ${habit} मार्क करें', '${applicationName} में आदत पूरी करें',
        '${applicationName} में आदत जोड़ें', '${applicationName} में रिमाइंडर जोड़ें', '${applicationName} में नई आदत',
        '${applicationName} में क्या बाकी है', '${applicationName} में आज क्या बाकी है',
        '${applicationName} में मेरा मूड दर्ज करें', '${applicationName} में मूड चेक-इन',
        '${applicationName} में ${habit} का टाइमर शुरू करें', '${applicationName} में आदत का टाइमर शुरू करें'],
 'pl': ['Odhacz ${habit} w ${applicationName}', 'Zaznacz ${habit} w ${applicationName}', 'Odhacz nawyk w ${applicationName}',
        'Dodaj nawyk w ${applicationName}', 'Dodaj przypomnienie w ${applicationName}', 'Nowy nawyk w ${applicationName}',
        'Co zostało w ${applicationName}', 'Co zostało na dziś w ${applicationName}',
        'Zapisz mój nastrój w ${applicationName}', 'Mój nastrój w ${applicationName}',
        'Uruchom minutnik ${habit} w ${applicationName}', 'Uruchom minutnik nawyku w ${applicationName}'],
 'id': ['Tandai ${habit} di ${applicationName}', 'Selesaikan ${habit} di ${applicationName}', 'Tandai kebiasaan di ${applicationName}',
        'Tambah kebiasaan di ${applicationName}', 'Tambah pengingat di ${applicationName}', 'Kebiasaan baru di ${applicationName}',
        'Apa yang tersisa di ${applicationName}', 'Apa yang tersisa hari ini di ${applicationName}',
        'Catat suasana hatiku di ${applicationName}', 'Cek suasana hati di ${applicationName}',
        'Mulai timer ${habit} di ${applicationName}', 'Mulai timer kebiasaan di ${applicationName}'],
})
for _lang, _phrases in SHORTCUTS.items():
    assert len(_phrases) == len(SHORTCUT_KEYS), ('shortcuts', _lang, len(_phrases))
    for _key, _value in zip(SHORTCUT_KEYS, _phrases):
        for _token in ('${applicationName}', '${habit}'):
            assert (_token in _key) == (_token in _value), ('shortcut token', _lang, _key)

def esc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')

def xml(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

for lang in ['en'] + LANGS + EXTRA:
    d = OUT + lang + '.lproj/'
    os.makedirs(d, exist_ok=True)
    info = f'"CFBundleDisplayName" = "{esc(NAMES[lang])}";\n"CFBundleName" = "{esc(NAMES[lang])}";\n'
    for key, texts in PERMISSIONS.items():
        info += f'"{key}" = "{esc(texts[lang])}";\n'
    open(d + 'InfoPlist.strings', 'w', encoding='utf-8').write(info)
    if lang in SHORTCUTS:
        with open(d + 'AppShortcuts.strings', 'w', encoding='utf-8') as f:
            for key, value in zip(SHORTCUT_KEYS, SHORTCUTS[lang]):
                f.write(f'"{esc(key)}" = "{esc(value)}";\n')
    if lang != 'en':
        with open(d + 'Localizable.strings', 'w', encoding='utf-8') as f:
            for k in sorted(rows):
                if lang in extra:
                    value = extra[lang].get(k, k)
                else:
                    value = rows[k][LANGS.index(lang)]
                f.write(f'"{esc(k)}" = "{esc(value)}";\n')
    parts = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
             '<plist version="1.0">', '<dict>']
    for key, forms in P.items():
        fm = forms[lang]
        parts += [f'\t<key>{xml(key)}</key>', '\t<dict>',
                  '\t\t<key>NSStringLocalizedFormatKey</key>', '\t\t<string>%1$#@value@</string>',
                  '\t\t<key>value</key>', '\t\t<dict>',
                  '\t\t\t<key>NSStringFormatSpecTypeKey</key>', '\t\t\t<string>NSStringPluralRuleType</string>',
                  '\t\t\t<key>NSStringFormatValueTypeKey</key>', '\t\t\t<string>lld</string>']
        for cat in ['zero', 'one', 'two', 'few', 'many', 'other']:
            if cat in fm:
                parts += [f'\t\t\t<key>{cat}</key>', f'\t\t\t<string>{xml(fm[cat])}</string>']
        parts += ['\t\t</dict>', '\t</dict>']
    parts += ['</dict>', '</plist>', '']
    open(d + 'Localizable.stringsdict', 'w', encoding='utf-8').write('\n'.join(parts))

# Check that every UI string in code has a translation
STRING_ARGS = {'habitName', 'summary', 'time', 'names', 'text', 'days', 'repeats', 'standard', 'event.summary ?? ""', 'inlineName(code)'}
lit = re.compile(r'"((?:[^"\\]|\\.|\\\([^)]*\))*)"')
def to_key(v):
    def r(m):
        e = m.group(1)
        return '%@' if (e in STRING_ARGS or e.startswith('Fmt.')) else '%lld'
    return re.sub(r'\\\(([^)]*\)?)\)', r, v)
ignore = {'ALTAppGroups', 'folder', 'siriTipHabitDetail', 'waveform', 'CFBundleShortVersionString', 'CFBundleVersion', 'EEEEdMMMM', 'HABIT_DONE', 'HABIT_REMINDER',
          'HABIT_SKIP', 'LLLLyyyy', 'PRO', 'ProgressWidget', 'TodayWidget', 'appex', 'dMMM', 'dMMMM', 'dMMMMyyyy',
          'habitID', 'habits-data.json', 'ungrouped', 'day', 'Habits Pro', 'AppleLanguages', 'all', 'appLanguage',
          'checkmark', 'de', 'en', 'es', 'fr', 'hi', 'ja', 'ko', 'ru', 'zh-Hans', 'pt-BR', 'it', 'tr', 'pl', 'id', 'system', 'summary', 'summary|%lld',
          'habits-backup-%lld.json', 'English', 'Deutsch', 'Español', 'Français', 'Português (Brasil)', 'Italiano', 'Türkçe', 'Polski', 'Bahasa Indonesia', 'Not checked off yet: \\(event.summary ?? '}
known = set(rows) | set(P) | ignore
missing = set()
files = glob.glob(ROOT + 'Habits/**/*.swift', recursive=True) + glob.glob(ROOT + 'HabitsWidget/*.swift') + glob.glob(ROOT + 'Shared/*.swift')
for f in files:
    for line in open(f, encoding='utf-8'):
        t = line.strip()
        if t.startswith('//') or t.startswith('print('):
            continue
        for m in lit.finditer(line):
            v = m.group(1)
            if not re.search(r'[A-Za-z]{2,}', re.sub(r'\\\([^)]*\)', '', v)):
                continue
            pre = line[:m.start()]
            if re.search(r'(systemName:|systemImage:|Image\(|\.symbol\(|"habitID"\]?)\s*$', pre) or re.fullmatch(r'[a-z0-9]+(\.[a-z0-9]+)+', v):
                continue
            if v in ('bicycle', 'calendar', 'globe', 'infinity', 'laptopcomputer', 'nosign', 'pencil', 'sparkles', 'target', 'timer'):
                continue
            if v.startswith('habits-data-broken') or re.fullmatch(r'[a-z]{2}-[A-Z]{2}', v):
                continue
            k = to_key(v)
            if k not in known:
                missing.add(k)
print('rows:', len(rows), 'missing:', sorted(missing))
