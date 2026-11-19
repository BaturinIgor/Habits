# App Review Information

Заполняется на странице версии, блок **App Review Information**.

- **Sign-in required**: снять галочку (аккаунтов нет).
- **Contact Information**: имя, фамилия, телефон с кодом страны, email. Это видит только Apple.
- **Notes**: текст ниже, на английском.

Текст для 1.6. Если версия уходит без часов (PR #30) или без статистики Firebase (PR #33), убери пункты 1-3 или 7 и строку про WatchConnectivity.

```
ZenHab is a habit tracker. There is no account and no own server. Habits are stored on the device (app group shared with the widgets) and, if the user is signed in to iCloud, in the user's own iCloud (CloudKit private database for the automatic backup, shared database for family groups).

New in 1.6:
1. Apple Watch app (watchOS 10 or later). It is installed together with the iPhone app; if it does not appear on the watch automatically, open the Watch app on the iPhone > My Watch > Available Apps > ZenHab > Install.
   How to test: with a paired Apple Watch, open ZenHab on the iPhone and add a habit (Today tab > "+", or pick one from the catalog). Open ZenHab on the watch: today's habits are listed. Tap a habit to check it off; for a habit with a daily count (Pro "Daily goal", e.g. 8 glasses of water) each tap adds +1. The check-off appears on the iPhone a moment later, and a check-off made on the iPhone appears on the watch. If the watch shows "Open ZenHab on your iPhone to see your habits here", open the app on the iPhone once while the watch is nearby. Check-offs made while the iPhone is out of reach are kept on the watch and synced later (WatchConnectivity, no server).
2. Complications: long-press the watch face > Edit > Complications and choose ZenHab. Circular, corner, rectangular and inline families show today's progress (done / total); the rectangular one is also available in the Smart Stack.
3. Habit timer on the watch (Pro): on the iPhone, open the habit editor (Habits tab > habit > Edit) > section "Timer" (requires Pro) and set the minutes. On the watch a timer button appears next to that habit; when time is up the watch plays a haptic and checks the habit off. Without Pro the watch shows "Available with Pro". To unlock Pro, buy any Pro product in the sandbox on the iPhone (Settings > "Habit Tracker Pro"); the Pro status is sent to the watch automatically.
4. Month in review and Year in review: Statistics tab > "Month in review" / "Year in review" buttons, shared as a picture with the share button on the card. The buttons appear once habits have existed for at least 7 days of the previous month (month) or of the current/previous year (year). On a fresh install, create a daily habit and set its "Start" date in the habit editor to two months ago; both buttons then appear in Statistics. During the first 3 days of a month the recap is also offered as a banner on the Today tab.
5. Shared pictures (week/month/year in review, achievements, family group cards) now include a QR code and are shared together with a link to the app's App Store page.
6. All pets are redrawn with new art and animations (tap the pet on the Today tab). The pet screen is now fully localized.
7. Anonymous usage statistics (Google Analytics for Firebase). The app sends screen views, taps and feature usage events with no personal content: no habit names, notes, mood entries or any typed text, no account data. The advertising identifier (IDFA) is not used, AdSupport is not linked, ad personalization and ad signals are disabled, and the data is not used for tracking, so there is no App Tracking Transparency prompt. Users can turn statistics off in Settings > "Share anonymous statistics". This is reflected in the privacy policy and the App Privacy answers (Device ID, Coarse Location, Purchase History, Product Interaction; analytics only, not linked to the user, not used for tracking).

Pro features: Settings > "Habit Tracker Pro". Monthly and yearly auto-renewable subscriptions and a lifetime non-consumable purchase; the sandbox purchase unlocks Pro immediately. The free version allows up to 5 active habits. "Restore purchases", Terms of Use and Privacy Policy links are on the same screen.

Features from earlier versions (Apple Health and the habit timer with a Live Activity, both Pro; quit mode; week in review; Control Center and Action button controls; iCloud backup; mood journal; Face ID lock; CSV export) work as before.

Sparks are points earned only by checking off habits. They cannot be bought with real money and have no cash value.

Background modes: "fetch" (BGAppRefreshTask) reschedules local reminders, refreshes widgets and checks Apple Health goals; "remote-notification" receives CloudKit change notifications for family groups. The watch app uses WatchConnectivity only and needs no extra background mode.

Feedback (Settings > Feedback) is sent only when the user taps Send: the text the user typed, an optional screenshot they pick and optional technical info (app version, iOS version, device model) go to the developer's support chat over HTTPS.
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
| 2.5.1 HealthKit | Здоровье не упомянуто в описании или данные уходят в iCloud | Health упомянут в описании (en, ru) и Notes; данные Health только читаются на устройстве и никуда не сохраняются |
| 2.5.4 / 4.0 Live Activity | Live Activity без пользы | Только таймер, который запустил сам пользователь, с концом отсчёта |
| Privacy manifest | Нет PrivacyInfo.xcprivacy при использовании UserDefaults | Добавлен `Shared/PrivacyInfo.xcprivacy` |
| 2.1 / 4.2 Apple Watch | Часы пустые или не работают у ревьюера | В Notes пошагово: добавить привычку на iPhone, отметить на часах, компликации, таймер с Pro через sandbox-покупку |
| 2.3.1 Metadata | В описании функции, которых нет в сборке | Apple Watch упомянут в описании, промотексте и «Что нового»: если часы не войдут в 1.6, убери эти строки |
| 5.1.1 / 5.1.2 Analytics | Сбор данных не совпадает с App Privacy и политикой | Firebase: ответы App Privacy в privacy-and-rating.md (раздел 1.6), политика обновляется в PR #33, выключатель в Настройках |

Если всё же отклонят, ответ приходит в App Store Connect -> Resolution Center. Пришли его текст в тред, разберём.
