#!/bin/bash
# Кладёт GoogleService-Info.plist в приложение перед xcodegen (только сборка для App Store).
# Берётся из секрета GOOGLE_SERVICE_INFO_PLIST (содержимое файла или base64), иначе из
# tools/analytics/GoogleService-Info.plist. Без файла статистика в приложении выключена.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="Habits/Resources/GoogleService-Info.plist"
if [ -n "${GOOGLE_SERVICE_INFO_PLIST:-}" ]; then
  if printf '%s' "$GOOGLE_SERVICE_INFO_PLIST" | grep -q "<plist"; then
    printf '%s' "$GOOGLE_SERVICE_INFO_PLIST" > "$DEST"
  else
    printf '%s' "$GOOGLE_SERVICE_INFO_PLIST" | base64 --decode > "$DEST"
  fi
elif [ -f "$DIR/GoogleService-Info.plist" ]; then
  cp "$DIR/GoogleService-Info.plist" "$DEST"
else
  echo "::warning::GoogleService-Info.plist не найден: статистика в этой сборке выключена."
  exit 0
fi
/usr/libexec/PlistBuddy -c "Print :BUNDLE_ID" "$DEST" >/dev/null
echo "Firebase Analytics подключён."
