#!/bin/bash
# Записывает App ID TelemetryDeck в Info.plist после xcodegen (только сборка для App Store).
# Берётся из переменной TELEMETRYDECK_APP_ID (Variables в GitHub), иначе из файла
# tools/analytics/telemetrydeck_app_id.txt. App ID не секрет: он всё равно есть внутри приложения.
# Без App ID статистика в приложении просто выключена.
set -euo pipefail
PLIST="${1:-Habits/Info.plist}"
DIR="$(cd "$(dirname "$0")" && pwd)"
ID="${TELEMETRYDECK_APP_ID:-}"
if [ -z "$ID" ] && [ -f "$DIR/telemetrydeck_app_id.txt" ]; then
  ID="$(tr -d '[:space:]' < "$DIR/telemetrydeck_app_id.txt")"
fi
if [ -z "$ID" ]; then
  echo "::warning::App ID TelemetryDeck не задан: статистика в этой сборке выключена."
  exit 0
fi
/usr/libexec/PlistBuddy -c "Set :TelemetryDeckAppID $ID" "$PLIST"
echo "Статистика TelemetryDeck подключена."
