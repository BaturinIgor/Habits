"""Добавляет системный тип cloudkit.share в схему CloudKit (файл .ckdb из cktool export-schema).

В Production новые типы не создаются, а cloudkit.share появляется в Development
только после первого приглашения из отладочной сборки. Наши сборки сразу идут
в Production, поэтому тип добавляем в схему сами и выкатываем вместе с остальными.

Использование: python3 add_share_type.py current.ckdb new.ckdb
"""
import sys

SHARE = '''
    RECORD TYPE cloudkit.share (
        "___createTime" TIMESTAMP,
        "___createdBy"  REFERENCE,
        "___etag"       STRING,
        "___modTime"    TIMESTAMP,
        "___modifiedBy" REFERENCE,
        "___recordID"   REFERENCE QUERYABLE,
        "cloudkit.title" STRING,
        "cloudkit.type" STRING,
        "cloudkit.thumbnailImageData" BYTES,
        GRANT WRITE TO "_creator",
        GRANT CREATE TO "_icloud",
        GRANT READ TO "_world"
    );
'''

FAMILY_TYPES = ['FamilyGroup', 'FamilyHabit', 'FamilyCheckIn']

TYPE = '''
    RECORD TYPE {name} (
        "___createTime" TIMESTAMP,
        "___createdBy"  REFERENCE,
        "___etag"       STRING,
        "___modTime"    TIMESTAMP,
        "___modifiedBy" REFERENCE,
        "___recordID"   REFERENCE QUERYABLE,
        json            BYTES,
        GRANT WRITE TO "_creator",
        GRANT CREATE TO "_icloud",
        GRANT READ TO "_world"
    );
'''

src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding='utf-8').read().rstrip() + '\n'
if 'DEFINE SCHEMA' not in text:
    text = 'DEFINE SCHEMA\n' + text
for name in FAMILY_TYPES:
    if f'RECORD TYPE {name} ' not in text and f'RECORD TYPE {name}(' not in text:
        print(f'add {name}')
        text += TYPE.format(name=name)
if 'RECORD TYPE cloudkit.share' not in text:
    print('add cloudkit.share')
    text += SHARE
else:
    print('cloudkit.share already there')
open(dst, 'w', encoding='utf-8').write(text)
