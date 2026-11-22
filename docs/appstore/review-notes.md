# App Review Information

Заполняется на странице версии, блок **App Review Information**.

- **Sign-in required**: снять галочку (аккаунтов нет).
- **Contact Information**: имя, фамилия, телефон с кодом страны, email. Это видит только Apple.
- **Notes**: текст ниже, на английском.

Текст для 1.7. Загрузка: Actions -> App Store texts с `overwrite`, скрипт берёт первый блок кода из этого файла (до 4000 символов).

Перед загрузкой:
- поток `offer` заменяет строку `<!-- offer: ... -->` в блоке на механику новогоднего предложения и шаги для ревьюера. Пока строка в блоке, заметки не загружать: Apple увидит её как есть;
- названия кнопок и разделов в кавычках («Continue for free», где в Статистике инсайты настроения, список интентов Siri) сверить с английскими строками в сборке 1.7;
- если что-то из списка «New in 1.7» не вошло в сборку, убрать пункт (иначе 2.3.1).

```
ZenHab is a habit tracker. There is no account and no own server. Habits are stored on the device (app group shared with the widgets) and, if the user is signed in to iCloud, in the user's own iCloud (CloudKit private database for the backup, shared database for family groups).

New in 1.7:
1. Onboarding with goal programs (shown on first launch; to see it again, delete and reinstall the app). The user picks a goal and gets a ready-made set of habits, which can be edited or removed later.
2. Paywall at the end of onboarding. "Continue for free" is visible right away, without scrolling or waiting; it closes the paywall and opens the app with the chosen habits. Everything except Pro features works without a purchase. The paywall shows prices, period, auto-renewal terms, "Restore purchases", Terms of Use and Privacy Policy.
3. New Year offer on Pro:
<!-- offer: how the offer works (introductory offer / promo price, dates, eligibility) and exact steps for the reviewer to see it in the sandbox -->
4. Smart reminders: the reminder time adapts to when the user actually checks a habit off. Local notifications only, computed on the device.
5. Mood insights: Statistics shows which habits go together with a better mood, based on mood entries and check-offs. Computed on the device, nothing is sent.
6. Siri and Shortcuts (App Intents): check off a habit, log mood, start a habit timer, what's left today. Habits are indexed in Spotlight (on-device only). Try: Shortcuts app > ZenHab.
7. Better layouts with large Dynamic Type sizes and VoiceOver labels.

Apple Health (HealthKit, read-only): Settings > "Apple Health" (visible to all users, with the Health heart icon) explains the integration and lists the data ZenHab reads (steps, exercise minutes, mindful minutes, sleep, water, workouts) and the linked habits. To link a habit (Pro): open a habit > "Apple Health" section > "Check off by" > pick a metric and a goal; iOS then asks for read access. When the goal is reached in Health, the habit is checked off by itself, and its row on the Today tab shows the progress with a heart icon. ZenHab never writes to Health; Health data is not stored or sent anywhere.

Apple Watch app (since 1.6), installed with the iPhone app: tap a habit on the watch, the check-off appears on the iPhone and vice versa (WatchConnectivity, no server). Complications: long-press the watch face > Edit > Complications > ZenHab.

Pro: Settings > "Habit Tracker Pro". Monthly and yearly auto-renewable subscriptions and a lifetime non-consumable purchase; the sandbox purchase unlocks Pro immediately. The free version allows up to 5 active habits.

Sparks are points earned only by checking off habits. They cannot be bought with real money and have no cash value.

Anonymous usage statistics (Google Analytics for Firebase): screen views, taps and feature usage only; no habit names, notes, mood entries or typed text. IDFA is not used, no tracking, so no ATT prompt. Off switch: Settings > "Share anonymous statistics".

Background modes: "fetch" (BGAppRefreshTask) reschedules local reminders, refreshes widgets and checks Apple Health goals; "remote-notification" receives CloudKit change notifications for family groups.

Feedback (Settings > Feedback) is sent only when the user taps Send, to the developer's support chat over HTTPS.
```

## Частые причины отказа и как они уже закрыты

| Правило | Что проверяют | Статус |
|---|---|---|
| 2.1 App Completeness | Покупки не грузятся у ревьюера | Подпиши Paid Apps Agreement и прикрепи покупки к версии (см. in-app-purchases.md) |
| 2.3.8 Metadata | Имя под иконкой не похоже на имя в магазине | Под иконкой ZenHab, в магазине "ZenHab: ..." |
| 3.1.2 Subscriptions | На экране покупки нет цены, срока, условий, ссылок | Экран Pro показывает цены, период, текст об автопродлении, Restore, Terms и Privacy |
| 3.1.2 Metadata | Нет ссылки на Terms of Use в описании | Ссылка на стандартное соглашение Apple есть в каждом описании |
| 5.1.1 Privacy | Нет политики конфиденциальности | `docs/privacy.html` на GitHub Pages, ссылка в приложении и в App Store Connect |
| 5.1.1(v) Account deletion | Есть регистрация без удаления аккаунта | Аккаунтов нет |
| 4.2 Minimum functionality | "Слишком простое приложение" | Виджеты, уведомления с действиями, статистика, питомец, слова |
| 2.5.4 Background modes | Фоновый режим без причины | Объяснено в Notes |
| 2.5.1 HealthKit | Здоровье не обозначено в интерфейсе (отказ 1.6, 20.11.2026), не упомянуто в описании или данные уходят в iCloud | Настройки → «Apple Health» видно всем, раздел Apple Health с иконкой в редакторе, сердце в строке на «Сегодня»; путь описан в Notes. Health упомянут в описании; данные Health только читаются и никуда не сохраняются |
| 2.5.4 / 4.0 Live Activity | Live Activity без пользы | Только таймер, который запустил сам пользователь, с концом отсчёта |
| Privacy manifest | Нет PrivacyInfo.xcprivacy при использовании UserDefaults | Добавлен `Shared/PrivacyInfo.xcprivacy` |
| 2.1 / 4.2 Apple Watch | Часы пустые или не работают у ревьюера | В Notes пошагово: добавить привычку на iPhone, отметить на часах, компликации, таймер с Pro через sandbox-покупку |
| 3.1.2 / 5.6 Paywall в онбординге | Пейволл мешает пользоваться бесплатно, кнопку закрытия не видно | «Continue for free» видна сразу, без задержки и прокрутки; бесплатная версия работает без покупки; путь описан в Notes (п. 2) |
| 3.1.1 / 2.3.2 Предложение | Предложение не видно у ревьюера, цены и сроки не совпадают с ASC | Механику и шаги дописывает поток `offer` (заглушка в Notes, п. 3); оффер заведён в App Store Connect до отправки |
| 2.3.1 Metadata | В описании функции, которых нет в сборке | В 1.7 описание и «Что нового» упоминают цели в онбординге, умные напоминания, инсайты настроения, Siri/Spotlight и новогоднее предложение: если что-то не вошло в сборку, убери строки |
| 5.1.1 / 5.1.2 Analytics | Сбор данных не совпадает с App Privacy и политикой | Firebase: ответы App Privacy в privacy-and-rating.md (раздел 1.6), политика обновляется в PR #33, выключатель в Настройках |

Если всё же отклонят, ответ приходит в App Store Connect -> Resolution Center. Пришли его текст в тред, разберём.
