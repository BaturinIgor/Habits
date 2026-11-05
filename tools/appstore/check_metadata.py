#!/usr/bin/env python3
"""Проверяет тексты для App Store в docs/appstore/metadata: все поля на месте и влезают в лимиты.

Запуск: python3 tools/appstore/check_metadata.py
"""
import glob
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
LIMITS = {
    'Name': 30,
    'Subtitle': 30,
    'Promotional text': 170,
    'Keywords': 100,
    'Description': 4000,
    "What's New": 4000,
}


def parse(path):
    fields, current = {}, None
    for line in open(path, encoding='utf-8'):
        line = line.rstrip('\n')
        if line.startswith('## '):
            current = line[3:].strip()
            fields[current] = []
        elif current:
            fields[current].append(line)
    return {k: '\n'.join(v).strip() for k, v in fields.items()}


errors = 0
for path in sorted(glob.glob(os.path.join(ROOT, 'docs/appstore/metadata/*.md'))):
    lang = os.path.basename(path)[:-3]
    fields = parse(path)
    report = []
    for name, limit in LIMITS.items():
        value = fields.get(name, '')
        if not value:
            report.append(f'{name}: пусто')
            errors += 1
            continue
        size = len(value)
        if size > limit:
            report.append(f'{name}: {size}/{limit} СЛИШКОМ ДЛИННО')
            errors += 1
        else:
            report.append(f'{name} {size}/{limit}')
    keywords = fields.get('Keywords', '')
    if ', ' in keywords:
        report.append('Keywords: убери пробелы после запятых, они съедают лимит')
        errors += 1
    words = [w for w in keywords.split(',') if w]
    if len(words) != len(set(words)):
        report.append('Keywords: есть повторы')
        errors += 1
    print(f'{lang:8} ' + ', '.join(report))

sys.exit(1 if errors else 0)
