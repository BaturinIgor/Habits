# Статистика ZenHab (Google Analytics for Firebase)

С версии 1.6 приложение шлёт анонимную статистику в Google Analytics for Firebase (продукт `FirebaseAnalyticsCore`
через Swift Package Manager: без IDFA/AdSupport и без GoogleAdsOnDeviceConversion; модуль всё равно `import FirebaseAnalytics`). Обёртка: `Habits/Features/Analytics.swift`, все имена событий
в `Habits/Features/AnalyticsCatalog.swift`. Лимита на число событий у Firebase нет, поэтому каждое
действие уходит своим событием, а Firebase сам отправляет их пачками.

## Что уходит

| Событие | Когда |
|---|---|
| `screen_view` (`screen_name`) | показ экрана; из этого Firebase считает время, сессии и пути между экранами |
| `gesture` (`screen`, `kind`: tap, longPress, swipeLeft/Right/Up/Down) | каждое нажатие и свайп в окне приложения, в том числе по пустому месту (это не только нажатия на кнопки). Активации через VoiceOver и другие спецвозможности не считаются: они не проходят как касания |
| `habit_check`, `habit_skip`, `pet_feed`, `data_export_csv`... (`screen`) | действия из `AnalyticsAction` |
| `app_installed`, `onboarding_completed`, `habit_created`, `habit_deleted`, `paywall_shown`, `purchase_started/completed/cancelled/failed`, `purchase_restored`, `pro_changed`, `pet_adopted`, `pet_stage_reached`, `achievement_unlocked`, `rating_prompt_shown`, `family_group_created/joined`, `feedback_sent`, `backup_restored` | важные события с параметрами из `AnalyticsEvent` |
| `daily_state` | раз в день: число привычек, групп, отметок и записей настроения за 7 дней, питомец, настройки |
| user properties `is_pro`, `first_seen_week` | для сравнения групп и когорт. `first_seen_week` и `daily_state.user_days_since_first_seen` считаются от первого запуска версии 1.6+, у обновившихся это не неделя установки (их отличает `app_installed.app_is_update = 1`) |

Лимиты Firebase: 500 разных событий, 25 параметров на событие, имена до 40 символов. Поэтому имена только из перечислений.

Личного не уходит никогда: ни названий привычек, ни заметок, ни настроения, ни имени питомца, ни названий групп, ни текста
(проверяет тест `testAnalyticsSendsNoPersonalText`, лимиты имён Firebase проверяет `testAnalyticsNamesFitFirebaseLimits`).
`daily_state` считается не на главном потоке, а жесты наблюдаются только при включённой статистике (`PerformanceTests.testAnalyticsIsCheap`). IDFA не собирается (AdSupport не подключён, ATT нет),
IDFV, рекламные сигналы и подмена делегата приложения выключены в `project.yml`.

## Включение

- `GoogleService-Info.plist` для bundle ID `com.baturinigor.zenhab`: секрет `GOOGLE_SERVICE_INFO_PLIST`
  (содержимое файла или base64) или файл `tools/analytics/GoogleService-Info.plist`.
  Кладётся только в сборку для App Store (`tools/analytics/add_firebase_config.sh "$APP_ID"`).
  Если секрета нет, он испорчен или plist выписан на другой bundle ID, сборка не падает: в логе warning, статистика выключена.
- Статистика выключена без файла, в UI- и юнит-тестах и в отладочной (Debug) сборке. Проверить события локально:
  положить plist в `Habits/Resources/`, `xcodegen generate`, запустить с аргументами `-AnalyticsDebug -FIRDebugEnabled`
  и смотреть Firebase → DebugView.
- Пользователь может выключить: Настройки → «Отправлять анонимную статистику» (переключатель виден, только когда Firebase подключён).
  Выключение останавливает отправку и стирает данные Firebase на устройстве (`resetAnalyticsData`), повторное включение
  сразу возвращает наблюдение жестов и свойства пользователя.
- Согласие: сейчас opt-out (собираем, пока пользователь не выключит). В Info.plist `FIREBASE_ANALYTICS_COLLECTION_ENABLED = false`,
  сбор включает только код. Перейти на opt-in: `Analytics.enabledByDefault = false` в `Habits/Features/Analytics.swift`
  (одна строка; тогда нужен и запрос согласия в интерфейсе).
- App Privacy в App Store Connect: Identifiers → Device ID, Location → Coarse Location,
  Purchases → Purchase History, Usage Data → Product Interaction. Везде Analytics, не связано, не для отслеживания.

## Еженедельный отчёт

Workflow `Weekly report` (понедельник 05:00 UTC и вручную) собирает установки, покупки, подписки
и доход из App Store Connect и шлёт короткую сводку в Telegram. Репозиторий публичный, поэтому отчёт не коммитится
и не печатается в лог: полный отчёт (.md и .json) лежит артефактом запуска 3 дня (артефакт может скачать любой
вошедший пользователь GitHub). Нужны секреты `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (ключ с ролью Sales,
Finance или Admin) и `ASC_VENDOR_NUMBER` (секрет или переменная). Без них workflow падает с понятной ошибкой
(`Не заданы секреты: ...`), секреты в лог не печатаются.
