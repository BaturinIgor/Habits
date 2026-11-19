# Статистика ZenHab (TelemetryDeck)

С версии 1.6 приложение шлёт анонимную статистику в TelemetryDeck. Клиент свой, без SDK:
`Habits/Features/Analytics.swift`, все имена событий и счётчиков в `Habits/Features/AnalyticsCatalog.swift`.

## Как экономятся события (бесплатный тариф: 50 000 в месяц)

- Экраны, время на них, переходы, нажатия, свайпы и действия только считаются в телефоне
  и раз в день уходят одним сигналом `Usage.daily` (счётчики лежат в его параметрах).
- Сразу (пачкой при уходе в фон) уходят только редкие события: `App.installed`, `Onboarding.completed`,
  `Habit.created`, `Habit.deleted`, `Paywall.shown`, `Purchase.*`, `Pro.changed`, `Pet.*`,
  `Achievement.unlocked`, `Rating.promptShown`, `Family.*`, `Feedback.sent`, `Backup.restored`.
- Итого около 50 сигналов на активного пользователя в месяц, то есть примерно 1 000 активных в месяц на бесплатном тарифе.

## Параметры `Usage.daily`

| Ключ | Что это |
|---|---|
| `Usage.day` | день, за который счётчики |
| `Session.count`, `Session.seconds` | открытия приложения и время в нём (секунды, ещё и в `floatValue`) |
| `Screen.<Экран>` | сколько раз открыт экран |
| `Time.<Экран>` | секунд на экране |
| `Flow.<A>><B>` | переходы между экранами |
| `Gesture.<Экран>.<tap/longPress/swipeLeft/...>` | все нажатия и свайпы по экранам |
| `Action.<...>` | действия: отметки, покупки за искры, питомец, экспорт и т. д. |
| `State.*` | состояние: сколько привычек, групп, отметок и записей настроения за 7 дней, питомец, настройки |
| `User.daysSinceInstall`, `User.installWeek`, `User.isPro` | для удержания и когорт |

Личного не уходит никогда: ни названий привычек, ни заметок, ни настроения, ни текста.
Это проверяет тест `testAnalyticsSendsNoPersonalText`.

## Включение

- App ID: переменная `TELEMETRYDECK_APP_ID` (Settings → Secrets and variables → Actions → Variables)
  или файл `tools/analytics/telemetrydeck_app_id.txt`. Подставляется только в сборке для App Store
  (`tools/analytics/inject_app_id.sh`). Без App ID и в автотестах статистика выключена.
- В отладочной сборке сигналы помечаются `isTestMode` и не смешиваются с настоящими.
- Пользователь может выключить: Настройки → «Отправлять анонимную статистику».

## Еженедельный отчёт

Workflow `Weekly report` (понедельник 05:00 UTC и вручную) собирает установки, покупки, подписки
и доход из App Store Connect, кладёт отчёт в ветку `analytics-reports` (`reports/weekly/<дата>.md`)
и шлёт короткую сводку в Telegram. Нужен `ASC_VENDOR_NUMBER` (секрет или переменная).
