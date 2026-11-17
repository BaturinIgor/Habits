# App Review Information

Заполняется на странице версии, блок **App Review Information**.

- **Sign-in required**: снять галочку (аккаунтов нет).
- **Contact Information**: имя, фамилия, телефон с кодом страны, email. Это видит только Apple.
- **Notes**: текст ниже, на английском.

```
ZenHab is a habit tracker. There is no account and no own server. Habits are stored on the device (app group shared with the widgets) and, if the user is signed in to iCloud, in the user's own iCloud (CloudKit private database for the automatic backup, shared database for family groups).

New in 1.4:
1. Apple Health (Pro): in the habit editor, section "Apple Health", link a habit to steps, sleep, water, workouts or mindful minutes and set a goal. The app only READS these values (no write access), compares them with the goal on the device and checks the habit off. Health data is never stored, sent to a server or saved to iCloud; only the fact that the habit was done is saved.
2. Habit timer (Pro): in the habit editor, section "Timer", set minutes. Tapping the habit on the Today tab opens the timer; it shows a Live Activity on the Lock Screen and in the Dynamic Island and checks the habit off when time is up.
3. Quit mode: in the habit editor turn on "I'm quitting this habit". The habit then shows days without it, the record and milestones.
4. Streak repair: the day after a missed day, a broken streak can be restored for 40 sparks.
5. Week in review: Statistics tab > "Week in review" card, can be shared as an image.
6. Control Center control and Action button (iOS 18): check off a habit without opening the app.
7. Automatic iCloud backup: Settings > Backup. On a new iPhone the app offers to restore.

Pro features: Settings > "Habit Tracker Pro". Monthly and yearly auto-renewable subscriptions and a lifetime non-consumable purchase; the sandbox purchase unlocks Pro immediately. The free version allows up to 5 active habits. "Restore purchases", Terms of Use and Privacy Policy links are on the same screen.

Sparks are points earned only by checking off habits. They cannot be bought with real money and have no cash value.

Background modes: "fetch" (BGAppRefreshTask) reschedules local reminders, refreshes widgets and checks Apple Health goals; "remote-notification" receives CloudKit change notifications for family groups.

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

Если всё же отклонят, ответ приходит в App Store Connect -> Resolution Center. Пришли его текст в тред, разберём.
