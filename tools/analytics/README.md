# Статистика ZenHab (Google Analytics for Firebase)

С версии 1.6 приложение шлёт анонимную статистику в Google Analytics for Firebase (продукт `FirebaseAnalyticsCore`
через Swift Package Manager: без IDFA/AdSupport и без GoogleAdsOnDeviceConversion; модуль всё равно `import FirebaseAnalytics`). Обёртка: `Habits/Features/Analytics.swift`, все имена событий
в `Habits/Features/AnalyticsCatalog.swift`. Лимита на число событий у Firebase нет, поэтому каждое
действие уходит своим событием, а Firebase сам отправляет их пачками. Нажатия и свайпы (их сотни) с 1.7 уходят
одним событием `gestures` за заход в приложение (KAN-167).

## Что уходит

| Событие | Когда |
|---|---|
| `screen_view` (`screen_name`) | показ экрана; из этого Firebase считает время, сессии и пути между экранами |
| `gestures` (`total`, `tap`, `long_press`, `swipe_left/right/up/down`) | одно событие за заход в приложение (уход в фон): сколько было нажатий и свайпов в окне, в том числе по пустому месту. Активации через VoiceOver не считаются: они не проходят как касания. До 1.7 было событие `gesture` на каждое нажатие |
| `habit_check`, `habit_uncheck`, `habit_increment`, `habit_skip`, `pet_feed`, `data_export_csv`... (`screen`) | действия из `AnalyticsAction`. `habit_increment` - +1 у привычки со счётчиком без достижения цели, `habit_uncheck` - только снятие выполненной отметки |
| `app_installed`, `onboarding_completed`, `habit_created`, `habit_deleted`, `purchase_started/cancelled/failed`, `purchase_restored`, `pro_changed`, `pet_adopted`, `pet_stage_reached`, `achievement_unlocked`, `family_group_created/joined`, `feedback_sent`, `backup_restored` | важные события с параметрами из `AnalyticsEvent` |
| `onboarding_step` (`step`: 1, 2, 3...) | показан шаг онбординга (каждый шаг один раз за запуск) |
| `notification_permission_result` (`result`: granted / denied) | ответ на системный запрос уведомлений (только когда запрос правда показан); то же в user property `notifications` |
| `first_check` (`seconds_since_first_open`, `value` = секунды) | первая выполненная отметка в приложении; -1, если момент первого запуска неизвестен. У тех, кто отмечал до 1.7, не уходит |
| `paywall_view` (`paywall_source`, `paywall_feature`) | показ пейволла. До 1.7: `paywall_shown` с источником-функцией |
| `purchase` (`paywall_source`, `purchase_product_id`, `value`, `currency`) | покупка прошла: стандартное событие GA4, доход виден в отчётах. До 1.7: `purchase_completed`. У `purchase_started/cancelled/failed` те же `paywall_source` и `purchase_product_id` |
| `review_prompt_shown` (`review_streak_days`) | показан системный запрос оценки (3 дня подряд с отметкой, раз на версию, не в онбординге и не поверх пейволла). До 1.7: `rating_prompt_shown` |
| `daily_state` | раз в день: число привычек, групп, отметок и записей настроения за 7 дней, питомец, настройки |
| user property `build_type` (debug / testflight / appstore) | тип сборки: TestFlight и установка из Xcode определяются по `AppTransaction.environment` (песочница). В отчётах GA4 смотреть только `appstore` (см. «Фильтр своего трафика») |
| user properties `is_pro`, `first_seen_week` | для сравнения групп и когорт. `first_seen_week` и `daily_state.user_days_since_first_seen` считаются от первого запуска версии 1.6+, у обновившихся это не неделя установки (их отличает `app_installed.app_is_update = 1`) |

Лимиты Firebase: 500 разных событий, 25 параметров на событие, имена до 40 символов. Поэтому имена только из перечислений.

Личного не уходит никогда: ни названий привычек, ни заметок, ни настроения, ни имени питомца, ни названий групп, ни текста
(проверяет тест `testAnalyticsSendsNoPersonalText`, лимиты имён Firebase проверяет `testAnalyticsNamesFitFirebaseLimits`).
`daily_state` считается не на главном потоке, а жесты наблюдаются и считаются только при включённой статистике (`PerformanceTests.testAnalyticsIsCheap`). IDFA не собирается (AdSupport не подключён, ATT нет),
IDFV, рекламные сигналы и подмена делегата приложения выключены в `project.yml`.

## Включение

- `GoogleService-Info.plist` для bundle ID `com.baturinigor.zenhab`: секрет `GOOGLE_SERVICE_INFO_PLIST`
  (содержимое файла или base64) или файл `tools/analytics/GoogleService-Info.plist`.
  Кладётся только в сборку для App Store (`tools/analytics/add_firebase_config.sh "$APP_ID"`).
  Если секрета нет, он испорчен или plist выписан на другой bundle ID, сборка не падает: в логе warning, статистика выключена.
- Статистика выключена без файла, в UI- и юнит-тестах, в отладочной (Debug) сборке и на симуляторе (KAN-167). Проверить события локально:
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
  События 1.7 (источник пейволла, ID продукта, цена, шаги онбординга, ответ на запрос уведомлений, первая отметка,
  тип сборки) укладываются в уже заявленные Purchase History и Product Interaction: менять App Privacy не нужно.

## Фильтр своего трафика в GA4 (KAN-167, делает владелец)

Код уже не шлёт события из Debug-сборок и симулятора и помечает каждого пользователя `build_type`. Свои TestFlight-устройства
отсекает фильтр по `build_type`, но для этого свойство надо один раз зарегистрировать в GA4 (нужен доступ «Редактор» к ресурсу):

1. analytics.google.com → ресурс ZenHab → Администратор (шестерёнка) → «Отображение данных» → «Специальные определения»
   → «Создать специальные параметры»: название `build_type`, область «Пользователь», свойство пользователя `build_type`. Сохранить.
2. Там же создать параметры области «Событие»: `paywall_source`, `paywall_feature`, `purchase_product_id`, `step`, `result`,
   `seconds_since_first_open` (последний лучше как «Специальный показатель», единица «Секунды»). Без этого их не видно в отчётах
   и в Data API. И параметр области «Пользователь» `notifications`.
3. Сравнение для отчётов: в любом отчёте → «Добавить сравнение» → `build_type` «точно соответствует» `appstore` → «Сохранить»
   (появится в списке сохранённых сравнений). В «Исследованиях» тот же фильтр ставится в «Фильтры» вкладки.
4. Внутренний трафик по IP (Администратор → «Потоки данных» → «Определить внутренний трафик») для приложений iOS не работает:
   он только для веб-потоков. Поэтому фильтр именно по `build_type`.
5. Данные до 1.7 (симулятор arm64 и свои устройства) свойства `build_type` не имеют: в сравнении `appstore` они не видны,
   а в старых отчётах их можно отсечь условием «Модель устройства ≠ arm64».

Значения регистрируются только для новых данных: отчёты по `build_type` начнут заполняться со следующего дня после шага 1.

## Воронка активации (KAN-168)

first_open → onboarding_completed → habit_created → first_check. Построить в GA4: «Исследования» → «Анализ последовательностей»
→ шаги: 1) `first_open`, 2) `onboarding_completed`, 3) `habit_created`, 4) `first_check`; «Открытая воронка» выключена,
разбивка по `build_type` или фильтр `build_type = appstore`. Где теряются внутри онбординга, видно по второй воронке
`onboarding_step` с `step` = 1, 2, 3... (нужен параметр `step` из шага 2 выше). Разрешение на уведомления по пользователям:
user property `notifications` или событие `notification_permission_result` с разбивкой по `result`.
Время до первой отметки: среднее `value` у `first_check` (секунды от первого запуска версии 1.6+, у новых пользователей
это и есть first_open).

## Еженедельный отчёт

Workflow `Weekly report` (понедельник 05:00 UTC и вручную) собирает установки, покупки, подписки
и доход из App Store Connect и шлёт сводку только в Telegram (секреты `FEEDBACK_BOT_TOKEN`, `FEEDBACK_CHAT_ID`).
Репозиторий публичный, поэтому отчёт не коммитится, не печатается в лог и не сохраняется артефактом.
Без настроенного Telegram запуск проходит успешно с сообщением «Telegram not configured, report not sent». Нужны секреты `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (ключ с ролью Sales,
Finance или Admin) и `ASC_VENDOR_NUMBER` (секрет или переменная). Без них workflow падает с понятной ошибкой
(`Не заданы секреты: ...`), секреты в лог не печатаются.

### Отдельный ключ для отчёта о продажах

Основной ключ App Store Connect (`ASC_KEY_*`) нужен сборкам и загрузке и не имеет доступа к финансам. Без доступа отчёт всё равно
уходит в Telegram, но вместо установок и дохода пишет «Продажи: нет доступа». Чтобы были цифры (владелец):

1. https://appstoreconnect.apple.com/access/integrations/api → «Team Keys» → «+» → имя `ZenHab weekly report`, доступ **Finance** → Generate.
2. Скачать .p8 (дают один раз), запомнить Key ID.
3. Секреты GitHub `ASC_REPORT_KEY_ID` (Key ID) и `ASC_REPORT_KEY_P8` (содержимое .p8):
   `gh secret set ASC_REPORT_KEY_ID --body "<Key ID>"` и `gh secret set ASC_REPORT_KEY_P8 < ~/Downloads/AuthKey_<Key ID>.p8`.
   Issuer ID тот же (`ASC_ISSUER_ID`). Workflow сам возьмёт отдельный ключ, если он задан.

### Пейволл по источнику (KAN-123)

Если заданы `GA4_PROPERTY_ID` (секрет или переменная, число из «Администратор → Сведения о ресурсе») и
`GA4_SERVICE_ACCOUNT_JSON` (ключ сервисного аккаунта Google Cloud, JSON или его base64), в отчёт и в Telegram добавляется
разбивка показов (`paywall_view`), покупок (`purchase`) и конверсии по `paywall_source` за ту же неделю, только для
`build_type = appstore` (пока свойство не зарегистрировано, по всем сборкам, это отмечено в заголовке раздела).
Без этих секретов раздел просто пропускается. Настроить (владелец):

1. console.cloud.google.com → проект (любой) → «APIs & Services» → включить «Google Analytics Data API».
2. «IAM & Admin» → «Service Accounts» → создать аккаунт → «Keys» → «Add key» → JSON, скачать.
3. GA4 → Администратор → «Управление доступом к ресурсу» → добавить email сервисного аккаунта с ролью «Читатель».
4. GitHub → Settings → Secrets and variables → Actions: `GA4_SERVICE_ACCOUNT_JSON` (содержимое JSON) и `GA4_PROPERTY_ID`.
5. В GA4 зарегистрировать параметр события `paywall_source` (шаг 2 раздела «Фильтр своего трафика»), иначе Data API вернёт ошибку.

Источники (`PaywallSource` в `PaywallView.swift`): `onboarding`, `settings`, `feature` (платная функция, какая - в `paywall_feature`),
`limit` (лимит бесплатных привычек), `pet`, `timer`, `recap`, `mood`, `new_year_offer`. `unknown` - версии до 1.7.
