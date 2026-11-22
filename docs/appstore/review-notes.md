# App Review Information

Заполняется на странице версии, блок **App Review Information**.

- **Sign-in required**: снять галочку (аккаунтов нет).
- **Contact Information**: имя, фамилия, телефон с кодом страны, email. Это видит только Apple.
- **Notes**: текст ниже, на английском.

Текст для 1.7. Загрузка: Actions -> App Store texts с `overwrite`, скрипт берёт первый блок кода из этого файла (до 4000 символов).

Перед загрузкой:
- названия кнопок и разделов в кавычках («Continue for free», где в Статистике инсайты настроения, список интентов Siri) сверить с английскими строками в сборке 1.7;
- если что-то из списка «New in 1.7» не вошло в сборку, убрать пункт (иначе 2.3.1).

```
ZenHab is a habit tracker. No account, no own server. Habits are stored on the device (app group shared with widgets) and in the user's own iCloud (CloudKit private database for backup, shared database for family groups).

New in 1.7:
1. Onboarding with goal programs (first launch; reinstall the app to see it again). The user picks a goal and gets a ready-made set of habits, which can be edited or removed later.
2. Paywall at the end of onboarding. "Continue for free" is visible right away, without scrolling or waiting, and opens the app with the chosen habits. Everything except Pro works without a purchase. The paywall shows prices, period, auto-renewal terms, "Restore purchases", Terms of Use and Privacy Policy.
3. Pro offers, all on the Pro Yearly subscription and set up in App Store Connect:
- Introductory offer: 1-week free trial for new subscribers. When the account is eligible, the Pro screen shows "Try Pro free for 7 days" and the button says "Start free trial".
- New Year offer: 50% off the first year, shown only from Dec 20, 2026 to Jan 10, 2027 (device date) and only without Pro. Purchase: custom offer code NEWYEAR2027 (valid until Jan 11, 2027) in Apple's redemption sheet. Promotional offer "newyear2027" has the same terms; the app only reads its price for display.
To see it now: iOS Settings > General > Date & Time, turn off "Set Automatically", pick Dec 20 - Jan 10, relaunch ZenHab, open Settings > "New Year offer" (also a card on Today). The Pro screen shows the yearly price crossed out, the first-year price and "Get the discount", which copies the code and opens the redemption sheet. If codes can't be redeemed in review, the regular yearly purchase there works in sandbox.
4. Smart reminder time (free): habit editor > reminder > "Smart time" moves the reminder closer to the usual check-off time; with it off, the habit screen may suggest it. Local notifications, computed on the device.
5. Mood insights (Pro): Statistics > "Mood journal" > "What goes with a better mood": habits that go with a better mood, from mood entries and check-offs. Without Pro it shows a lock. Computed on the device.
6. Siri and Shortcuts (App Intents): "Check off a habit", "Add a habit", "What's left today", "Log mood", "Start a habit timer" (Pro). Example: "Log my mood in ZenHab". Habits are indexed in Spotlight (on-device only). Try: Shortcuts app > ZenHab.
7. Better layouts with large Dynamic Type sizes and VoiceOver labels.

Apple Health (HealthKit, read-only): Settings > "Apple Health" (visible to all) lists the data ZenHab reads (steps, exercise and mindful minutes, sleep, water, workouts). To link a habit (Pro): habit > "Apple Health" > "Check off by" > metric and goal; iOS asks for read access. When the goal is reached, the habit is checked off and its Today row shows progress with a heart icon. ZenHab never writes to Health; Health data is not stored or sent.

Apple Watch app (since 1.6): a check-off on the watch appears on the iPhone and vice versa (WatchConnectivity). Complications: long-press the watch face > Edit > ZenHab.

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
| 3.1.1 / 2.3.2 Предложение | Предложение не видно у ревьюера, цены и сроки не совпадают с ASC | В Notes (п. 3) механика и шаги: пробная неделя, промо-предложение `newyear2027`, код NEWYEAR2027, как увидеть акцию сменой даты. До отправки в App Store Connect должны быть заведены пробный период, promotional offer `newyear2027` (−50% на первый год) и custom code NEWYEAR2027 до 11.01.2027 (workflow appstore-offers) |
| 2.3.1 Metadata | В описании функции, которых нет в сборке | В 1.7 описание и «Что нового» упоминают цели в онбординге, умные напоминания, инсайты настроения, Siri/Spotlight и новогоднее предложение: если что-то не вошло в сборку, убери строки |
| 5.1.1 / 5.1.2 Analytics | Сбор данных не совпадает с App Privacy и политикой | Firebase: ответы App Privacy в privacy-and-rating.md (раздел 1.6), политика обновляется в PR #33, выключатель в Настройках |

Если всё же отклонят, ответ приходит в App Store Connect -> Resolution Center. Пришли его текст в тред, разберём.
