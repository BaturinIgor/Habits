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
NAMES = {'en': 'Habit Tracker', 'ru': 'Трекер привычек', 'de': 'Gewohnheitstracker', 'fr': "Suivi d'habitudes",
         'es': 'Rastreador de hábitos', 'zh-Hans': '习惯追踪', 'ja': '習慣トラッカー', 'ko': '습관 트래커', 'hi': 'आदत ट्रैकर'}

def esc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')

def xml(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

for lang in ['en'] + LANGS:
    d = OUT + lang + '.lproj/'
    os.makedirs(d, exist_ok=True)
    open(d + 'InfoPlist.strings', 'w', encoding='utf-8').write(f'"CFBundleDisplayName" = "{esc(NAMES[lang])}";\n"CFBundleName" = "{esc(NAMES[lang])}";\n')
    if lang != 'en':
        i = LANGS.index(lang)
        with open(d + 'Localizable.strings', 'w', encoding='utf-8') as f:
            for k in sorted(rows):
                f.write(f'"{esc(k)}" = "{esc(rows[k][i])}";\n')
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
STRING_ARGS = {'days', 'repeats', 'standard', 'event.summary ?? ""'}
lit = re.compile(r'"((?:[^"\\]|\\.|\\\([^)]*\))*)"')
def to_key(v):
    def r(m):
        e = m.group(1)
        return '%@' if (e in STRING_ARGS or e.startswith('Fmt.')) else '%lld'
    return re.sub(r'\\\(([^)]*\)?)\)', r, v)
ignore = {'ALTAppGroups', 'CFBundleShortVersionString', 'CFBundleVersion', 'EEEEdMMMM', 'HABIT_DONE', 'HABIT_REMINDER',
          'HABIT_SKIP', 'LLLLyyyy', 'PRO', 'ProgressWidget', 'TodayWidget', 'appex', 'dMMM', 'dMMMM', 'dMMMMyyyy',
          'habitID', 'habits-data.json', 'ungrouped', 'day', 'Habits Pro', 'AppleLanguages', 'all', 'appLanguage',
          'checkmark', 'de', 'en', 'es', 'fr', 'hi', 'ja', 'ko', 'ru', 'zh-Hans', 'system', 'summary', 'summary|%lld',
          'habits-backup-%lld.json', 'English', 'Deutsch', 'Español', 'Français', 'Not checked off yet: \\(event.summary ?? '}
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
            if v.startswith('habits-data-broken'):
                continue
            k = to_key(v)
            if k not in known:
                missing.add(k)
print('rows:', len(rows), 'missing:', sorted(missing))
