# Ответы на анкеты App Store Connect

Всё ниже проверено по коду: приложение не ходит в сеть (кроме покупок через StoreKit и ссылок, которые открывает сам пользователь), не использует аналитику, рекламу и сторонние SDK.

## App Privacy (раздел "App Privacy" приложения)

1. **Privacy Policy URL**: `https://baturinigor.github.io/Habits/privacy.html`
2. **Do you or your third-party partners collect data from this app?** -> **No, we do not collect data from this app.**
3. Нажми Publish. На странице в App Store появится карточка "Data Not Collected".

Почему "No" честно:
- привычки, отметки, заметки, фото для аватарок хранятся только на устройстве;
- обратная связь уходит письмом из почтового приложения самого пользователя, по его желанию. Apple разрешает не указывать такие данные: это необязательная разовая передача по инициативе пользователя;
- покупки обрабатывает Apple, мы видим только факт покупки.

Если когда-нибудь добавишь аналитику, крашлитику (Firebase, Sentry и т. п.) или синхронизацию через свой сервер, ответы и `Shared/PrivacyInfo.xcprivacy` нужно будет обновить.

## Возрастной рейтинг (App Information -> Age Rating)

С 2025 года у Apple новая анкета и рейтинги 4+, 9+, 13+, 16+, 18+.

| Вопрос | Ответ |
|---|---|
| Parental Controls | No |
| Age Assurance | No |
| Unrestricted Web Access | No |
| User-Generated Content | No (заметки видит только сам пользователь) |
| Messaging and Chat | No |
| Advertising | No |
| Profanity or Crude Humor | None |
| Horror/Fear Themes | None |
| Alcohol, Tobacco, or Drug Use or References | None (в каталоге есть цели "Не курить" и "Без алкоголя", это отказ от привычки, а не употребление) |
| Mature or Suggestive Themes | None |
| Sexual Content or Nudity / Graphic Sexual Content | None |
| Cartoon or Fantasy Violence / Realistic Violence / Prolonged Graphic Violence | None |
| Guns or Other Weapons | None |
| Medical or Treatment Information | None |
| Health or Wellness Topics | Yes, если вопрос есть (привычки про воду, сон, спорт). Это не повышает рейтинг выше 4+ само по себе |
| Simulated Gambling / Gambling | No / None |
| Contests | None |
| Loot Boxes | No (питомцы и награды покупаются за искры по фиксированной цене, без случайности) |

Ожидаемый результат: **4+**. Если Apple покажет выше, ничего страшного, просто прими.

## Категория

- Primary: **Productivity**
- Secondary: **Health & Fitness**

## Content Rights (App Information)

"Does your app contain, show, or access third-party content?" -> **No**. Иконки из SF Symbols и эмодзи системные, словарь слов собран нами.

## Export Compliance (шифрование)

В `project.yml` уже стоит `ITSAppUsesNonExemptEncryption: false`, поэтому App Store Connect не будет спрашивать про шифрование у каждой сборки. Если спросит вручную: "Does your app use encryption?" -> **None of the algorithms mentioned above** (используется только шифрование самой iOS и HTTPS через системные API). Документы для Франции не нужны.

## Advertising Identifier (IDFA)

Не используется. Если спросят, отвечай **No**.

## Digital Services Act (ЕС) — статус трейдера

В Business -> Compliance (или при выборе стран) Apple спросит, являешься ли ты **trader**.
- Если продаёшь Pro (подписки и покупки), по правилам ЕС это обычно trader. Тогда Apple покажет в App Store ЕС твои имя, адрес, телефон и email, и их нужно подтвердить.
- Если не хочешь раскрывать адрес, можно на первое время убрать страны ЕС из Availability, а позже вернуть.

## Доступность (Pricing and Availability)

- Price: **Free** (деньги через Pro).
- Availability: все страны или выбранные. Для России учти: оплата в App Store там с 2022 года практически недоступна, но бесплатная часть приложения работает.
- Распространение на Mac с Apple Silicon и Vision Pro: можно снять галочки "Make this app available" для Mac и Vision, если не хочешь, чтобы его ставили не с iPhone. Приложение рассчитано только на iPhone.
