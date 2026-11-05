#!/usr/bin/env bash
# Меняет идентификатор приложения com.personal.habits на свой во всём проекте:
# bundle ID приложения и виджета, App Group, фоновую задачу и ID покупок Pro.
# Workflow appstore.yml запускает его перед сборкой для App Store, поэтому сборка для SideStore
# остаётся с прежними идентификаторами и данные на телефоне не теряются.
#
# Использование: tools/appstore/set_bundle_id.sh com.baturinigor.zenhab
set -euo pipefail

NEW_ID="${1:?Укажи новый идентификатор, например com.baturinigor.zenhab}"
OLD_ID="com.personal.habits"

if [[ ! "$NEW_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
  echo "Неверный идентификатор: $NEW_ID (нужны латинские буквы, цифры, дефисы и точки)" >&2
  exit 1
fi
[[ "$NEW_ID" == "$OLD_ID" ]] && { echo "Идентификатор уже $OLD_ID, менять нечего"; exit 0; }

cd "$(dirname "$0")/../.."
files=$(grep -rl --include='*.swift' --include='*.entitlements' --include='*.yml' -F "$OLD_ID" project.yml Habits HabitsWidget Shared || true)
for f in $files; do
  # Точки в старом ID экранированы, чтобы sed понимал их буквально.
  sed -i.bak "s/com\.personal\.habits/$NEW_ID/g" "$f" && rm -f "$f.bak"
  echo "  $f"
done
echo "Готово: $OLD_ID -> $NEW_ID"
