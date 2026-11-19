# Статистика ZenHab (Google Analytics for Firebase)

С версии 1.6 приложение шлёт анонимную статистику в Google Analytics for Firebase (SDK `FirebaseAnalytics`
через Swift Package Manager). Обёртка: `Habits/Features/Analytics.swift`, все имена событий
в `Habits/Features/AnalyticsCatalog.swift`. Лимита на число событий у Firebase нет, поэтому каждое
действие уходит своим событием, а Firebase сам отправляет их пачками.

## Что уходит

| Событие | Когда |
|---|---|
| `screen_view` (`screen_name`) | показ экрана; из этого Firebase считает время, сессии и пути между экранами |
| `gesture` (`screen`, `kind`: tap, longPress, swipeLeft/Right/Up/Down) | каждое нажатие и свайп |
| `habit_check`, `habit_skip`, `pet_feed`, `data_export_csv`... (`screen`) | действия из `AnalyticsAction` |
| `app_installed`, `onboarding_completed`, `habit_created`, `habit_deleted`, `paywall_shown`, `purchase_started/completed/cancelled/failed`, `purchase_restored`, `pro_changed`, `pet_adopted`, `pet_stage_reached`, `achievement_unlocked`, `rating_prompt_shown`, `family_group_created/joined`, `feedback_sent`, `backup_restored` | важные события с параметрами из `AnalyticsEvent` |
| `daily_state` | раз в день: число привычек, групп, отметок и записей настроения за 7 дней, питомец, настройки |
| user properties `is_pro`, `install_week` | для сравнения групп и когорт |

Лимиты Firebase: 500 разных событий, 25 параметров на событие, имена до 40 символов. Поэтому имена только из перечислений.

Личного не уходит никогда: ни названий привычек, ни заметок, ни настроения, ни текста
(проверяет тест `testAnalyticsSendsNoPersonalText`). IDFA не собирается (AdSupport не подключён, ATT нет),
IDFV, рекламные сигналы и подмена делегата приложения выключены в `project.yml`.

## Включение

- `GoogleService-Info.plist` для bundle ID `com.baturinigor.zenhab`: секрет `GOOGLE_SERVICE_INFO_PLIST`
  (содержимое файла или base64) или файл `tools/analytics/GoogleService-Info.plist`.
  Кладётся только в сборку для App Store (`tools/analytics/add_firebase_config.sh`).
  Без файла и в автотестах статистика выключена.
- Пользователь может выключить: Настройки → «Отправлять анонимную статистику».
- App Privacy в App Store Connect: Identifiers → Device ID, Location → Coarse Location,
  Purchases → Purchase History, Usage Data → Product Interaction. Везде Analytics, не связано, не для отслеживания.

## Еженедельный отчёт

Workflow `Weekly report` (понедельник 05:00 UTC и вручную) собирает установки, покупки, подписки
и доход из App Store Connect, кладёт отчёт в ветку `analytics-reports` (`reports/weekly/<дата>.md`)
и шлёт короткую сводку в Telegram. Нужен `ASC_VENDOR_NUMBER` (секрет или переменная).
