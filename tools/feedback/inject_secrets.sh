#!/bin/bash
# Записывает токен Telegram-бота и chat_id для отзывов в Info.plist после xcodegen.
# Значения не передаются в xcodebuild, чтобы не попасть в build.log.
# Без секретов ключи остаются пустыми, и форма отзыва работает через почту.
set -euo pipefail
PLIST="${1:-Habits/Info.plist}"
if [ -z "${FEEDBACK_BOT_TOKEN:-}" ] || [ -z "${FEEDBACK_CHAT_ID:-}" ]; then
  echo "::warning::FEEDBACK_BOT_TOKEN или FEEDBACK_CHAT_ID не заданы: отзывы будут уходить через почту."
  exit 0
fi
/usr/libexec/PlistBuddy -c "Set :FeedbackBotToken $FEEDBACK_BOT_TOKEN" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :FeedbackChatID $FEEDBACK_CHAT_ID" "$PLIST"
echo "Telegram-бот для отзывов подключён."
