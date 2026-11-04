"""Собирает словарь из tools/words/*.txt в Habits/Resources/words.tsv и проверяет его.

Формат строки: категория|en|ru|de|fr|es|pt-BR|it|tr|pl|id|zh-Hans|ja|ko|hi
Уровень задаётся строкой "#level N" в начале файла (0 начальный, 1 средний, 2 продвинутый),
без неё уровень 0. В words.tsv уровень пишется первой колонкой.
Английское слово - постоянный ключ прогресса, поэтому его нельзя менять у уже
выпущенных слов. Новые слова добавляй в конец последнего файла или в новый файл.
"""
import glob, os
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
COLS = 15
out, seen = [], set()
for path in sorted(glob.glob(os.path.join(HERE, '*.txt'))):
    level = 0
    for n, line in enumerate(open(path, encoding='utf-8'), 1):
        line = line.strip()
        if line.startswith('#level'):
            level = int(line.split()[1])
            continue
        if not line or line.startswith('#'):
            continue
        parts = [p.strip() for p in line.split('|')]
        assert len(parts) == COLS, (os.path.basename(path), n, len(parts), line[:60])
        assert all(parts), (os.path.basename(path), n, 'empty column', line[:60])
        assert parts[1] not in seen, (os.path.basename(path), n, 'duplicate', parts[1])
        seen.add(parts[1])
        out.append(str(level) + '|' + '|'.join(parts))
dest = os.path.join(ROOT, 'Habits', 'Resources', 'words.tsv')
open(dest, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print('words:', len(out))
