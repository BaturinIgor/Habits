#!/usr/bin/env bash
# Включает семейные группы (iCloud, CloudKit) и Apple Health в сборке для App Store:
# добавляет приложению права iCloud, push и HealthKit и ставит FamilySharingEnabled и HealthEnabled.
# В App ID на developer.apple.com должны быть включены iCloud, Push Notifications и HealthKit,
# а профиль подписи должен быть выпущен после этого.
# Сборка для SideStore эти права получить не может, поэтому в project.yml их нет.
# Workflow appstore.yml запускает скрипт до set_bundle_id.sh, который потом заменит
# com.personal.habits и в имени контейнера iCloud.
set -euo pipefail
cd "$(dirname "$0")/../.."

python3 - <<'PY'
import re
path = 'project.yml'
text = open(path, encoding='utf-8').read()
if 'com.apple.developer.icloud-services' in text:
    print('Права iCloud уже добавлены')
    raise SystemExit
anchor = "          - group.com.personal.habits\n"
start = text.index('  Habits:\n')
pos = text.index(anchor, start) + len(anchor)
extra = (
    "        com.apple.developer.icloud-container-identifiers:\n"
    "          - iCloud.com.personal.habits\n"
    "        com.apple.developer.icloud-services:\n"
    "          - CloudKit\n"
    "        aps-environment: production\n"
    "        com.apple.developer.healthkit: true\n"
    "        com.apple.developer.healthkit.access: []\n"
)
text = text[:pos] + extra + text[pos:]
text, n = re.subn(r'FamilySharingEnabled: false', 'FamilySharingEnabled: true', text)
assert n == 1, 'FamilySharingEnabled не найден'
text, n = re.subn(r'HealthEnabled: false', 'HealthEnabled: true', text)
assert n == 1, 'HealthEnabled не найден'
open(path, 'w', encoding='utf-8').write(text)
print('Семейные группы включены')
PY
