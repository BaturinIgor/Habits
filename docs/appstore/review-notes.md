# App Review Information

Заполняется на странице версии, блок **App Review Information**.

- **Sign-in required**: снять галочку (аккаунтов нет).
- **Contact Information**: имя, фамилия, телефон с кодом страны, email. Это видит только Apple.
- **Notes**: текст ниже, на английском.

```
ZenHab is a habit tracker. It works fully offline: there is no account, no server and no third-party SDK. All data is stored on the device (app group container shared with the widget).

How to try the main features:
1. On first launch, finish the short onboarding, then tap "+" on the Today tab or pick habits from the catalog.
2. Set a reminder time a minute ahead to see the notification. If a habit is not checked off, the reminder repeats every 15 minutes; the Done and Skip buttons in the notification stop the repeats.
3. Add the ZenHab widget to the Home Screen: habits can be checked off directly from it (App Intents).
4. Profile tab: achievements, avatars, backgrounds and a virtual pet. "Sparks" are points earned only by checking off habits. They cannot be bought with real money and have no cash value.
5. Words: a built-in word-learning habit with an offline dictionary; pronunciation uses the system speech synthesizer.

In-app purchases: Settings > "Habit Tracker Pro". Pro is offered as monthly and yearly auto-renewable subscriptions and a lifetime non-consumable purchase. The free version allows up to 5 active habits. "Restore purchases", Terms of Use and Privacy Policy links are on the same screen.

Background: the app uses BGAppRefreshTask (UIBackgroundModes: fetch) only to reschedule local reminders and refresh widgets.

Feedback in Settings opens the user's own Mail app; nothing is sent automatically.
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
| Privacy manifest | Нет PrivacyInfo.xcprivacy при использовании UserDefaults | Добавлен `Shared/PrivacyInfo.xcprivacy` |

Если всё же отклонят, ответ приходит в App Store Connect -> Resolution Center. Пришли его текст в тред, разберём.
