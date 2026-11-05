# Публикация ZenHab в App Store

Пошаговая инструкция от аккаунта разработчика до кнопки "Отправить на проверку". Mac не нужен: сборка и загрузка идут через GitHub Actions. Если Mac с Xcode есть, в паре мест есть путь короче, он отмечен отдельно.

## Что лежит в этой папке

| Файл | Что внутри |
|---|---|
| `README.md` | Эта инструкция |
| `metadata/*.md` | Название, подзаголовок, промотекст, ключевые слова, описание и "Что нового" на 14 языках. Проверка лимитов: `python3 tools/appstore/check_metadata.py` |
| `in-app-purchases.md` | Как завести подписки и покупку Pro, ID, цены, тексты |
| `privacy-and-rating.md` | Ответы App Privacy, возрастной рейтинг, экспорт, категория, DSA |
| `review-notes.md` | Текст для ревьюера и частые причины отказа |
| `screenshots/` | Размеры, план скриншотов, подписи, проверка иконки |
| `../privacy.html`, `../support.html`, `../index.html` | Страницы для GitHub Pages: политика, поддержка, сайт |

В коде для App Store уже сделано:
- `.github/workflows/appstore.yml`: подписанная сборка и загрузка в App Store Connect по кнопке;
- `tools/appstore/set_bundle_id.sh`: подставляет твой идентификатор вместо `com.personal.habits` только в сборке для App Store, SideStore-сборка не меняется;
- `Shared/PrivacyInfo.xcprivacy`: манифест приватности, без него App Store Connect ругается на UserDefaults;
- имя под иконкой ZenHab;
- в App Store-сборке нет флага `SIDELOAD`, поэтому там работают настоящие покупки, а тестовый переключатель Pro скрыт.

## Чем App Store отличается от SideStore

| | SideStore сейчас | App Store |
|---|---|---|
| Аккаунт | Бесплатный Apple ID | Apple Developer Program, $99 в год |
| Подпись | ldid, SideStore переподписывает каждые 7 дней | Сертификат Apple Distribution и профили, подпись не истекает у пользователей |
| Идентификаторы | `com.personal.habits`, SideStore дописывает суффикс | Свои уникальные: `com.baturinigor.zenhab` |
| Покупки | Не работают, Pro включается переключателем | StoreKit, настоящие подписки |
| Сборка | `build.yml` на каждый push в main | `appstore.yml` вручную, когда хочешь выпустить версию |

Обе сборки могут стоять на одном iPhone одновременно: это разные приложения. Данные между ними не общие. Чтобы перенести свои привычки, в SideStore-версии сделай Настройки -> Экспорт данных и загрузи файл в App Store-версии.

## Шаг 1. Apple Developer Program

1. Включи двухфакторную аутентификацию на своём Apple Account.
2. Проще всего записаться через приложение **Apple Developer** на iPhone: Account -> Enroll Now. Тип: **Individual** (физлицо). Организация потребует D-U-N-S номер и юрлицо.
3. Оплата $99 в год. Карты российских банков Apple не принимает, нужна карта зарубежного банка.
4. Подтверждение занимает от нескольких часов до 2 дней. В магазине продавцом будет указано твоё имя латиницей так, как в документах.

## Шаг 2. Идентификаторы

Нужно выбрать bundle ID. Он навсегда, поменять после первой загрузки нельзя. Предлагаю `com.baturinigor.zenhab` (если выберешь другой, запиши его в переменную `APP_BUNDLE_ID` на шаге 6, всё остальное подстроится).

На [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers/list) создай три записи:

1. "+" -> **App Groups** -> Description `ZenHab Group`, Identifier `group.com.baturinigor.zenhab`.
2. "+" -> **App IDs** -> App -> Description `ZenHab`, Bundle ID **Explicit** `com.baturinigor.zenhab`. В Capabilities включи **App Groups**, нажми Configure и выбери группу из пункта 1. In-App Purchase включён по умолчанию.
3. Ещё один App ID: Description `ZenHab Widget`, Bundle ID `com.baturinigor.zenhab.widget`, тоже **App Groups** с той же группой.

Если Apple скажет, что ID занят, возьми другой (например `com.baturinigor.zenhab.app`) и используй его везде дальше.

## Шаг 3. Сертификат Apple Distribution

Один сертификат на аккаунт, действует год. Делается из любого компьютера с OpenSSL (на Windows есть в Git Bash).

```bash
mkdir zenhab-signing && cd zenhab-signing
openssl genrsa -out dist.key 2048
openssl req -new -key dist.key -out dist.csr -subj "/emailAddress=ТВОЙ_EMAIL/CN=Igor Baturin/C=RU"
```

1. На [Certificates](https://developer.apple.com/account/resources/certificates/list) нажми "+" -> **Apple Distribution** -> загрузи `dist.csr` -> скачай `distribution.cer` в ту же папку.
2. Собери из него p12 с паролем (придумай и запомни, он пойдёт в секрет):

```bash
openssl x509 -inform DER -in distribution.cer -out distribution.pem
openssl pkcs12 -export -legacy -inkey dist.key -in distribution.pem -out dist.p12 -name "Apple Distribution"
```

Если OpenSSL ответит "unknown option -legacy", это старая версия, просто убери `-legacy`.

`dist.key` и `dist.p12` никому не отправляй и не клади в репозиторий. Сохрани папку в надёжном месте: через год сертификат придётся продлить тем же способом.

С Mac проще: Xcode -> Settings -> Accounts -> Manage Certificates -> "+" -> Apple Distribution, потом в "Связке ключей" экспортировать его в .p12.

## Шаг 4. Профили подписи

На [Profiles](https://developer.apple.com/account/resources/profiles/list) создай два профиля:

1. "+" -> Distribution -> **App Store Connect** -> App ID `com.baturinigor.zenhab` -> сертификат из шага 3 -> имя `ZenHab AppStore` -> скачай.
2. То же для `com.baturinigor.zenhab.widget`, имя `ZenHab Widget AppStore`.

Профили действуют год, вместе с сертификатом. Если поменяешь capabilities у App ID, профили нужно перевыпустить и обновить в секретах.

## Шаг 5. Ключ App Store Connect API

Нужен, чтобы GitHub загружал сборки без твоего пароля.

1. [App Store Connect](https://appstoreconnect.apple.com) -> Users and Access -> **Integrations** -> App Store Connect API -> Team Keys -> "+" (при первом заходе нажми Request Access).
2. Name `GitHub`, Access **App Manager**.
3. Скачай `.p8`. Скачать можно только один раз. Запиши **Key ID** (в строке ключа) и **Issuer ID** (над таблицей).

## Шаг 6. Секреты в GitHub

Репозиторий -> Settings -> Secrets and variables -> Actions.

**Secrets** (New repository secret):

| Имя | Значение |
|---|---|
| `APPLE_TEAM_ID` | Team ID из [Membership details](https://developer.apple.com/account), 10 символов |
| `DIST_CERT_P12` | `dist.p12` в base64 |
| `DIST_CERT_PASSWORD` | Пароль от p12 |
| `PROFILE_APP` | `ZenHab_AppStore.mobileprovision` в base64 |
| `PROFILE_WIDGET` | Профиль виджета в base64 |
| `ASC_KEY_ID` | Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8` | Содержимое `.p8` целиком (открой в блокноте и скопируй) |

Как получить base64 файла:
- macOS: `base64 -i dist.p12 | pbcopy` (сразу в буфер обмена);
- Linux или Git Bash: `base64 -w0 dist.p12 > dist.txt`;
- Windows PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("dist.p12")) | Set-Clipboard`.

**Variables** (вкладка Variables), только если bundle ID не `com.baturinigor.zenhab`:

| Имя | Значение |
|---|---|
| `APP_BUNDLE_ID` | Твой bundle ID |

## Шаг 7. Сайт на GitHub Pages

После слияния этого PR: репозиторий -> Settings -> **Pages** -> Source **Deploy from a branch** -> Branch `main`, папка `/docs` -> Save. Через пару минут откроются:

- https://baturinigor.github.io/Habits/ (Marketing URL)
- https://baturinigor.github.io/Habits/support.html (Support URL, обязателен)
- https://baturinigor.github.io/Habits/privacy.html (Privacy Policy URL, обязателен; эта же ссылка уже зашита в приложение)

Почта поддержки на страницах и в приложении: `zdrgvretrsyhtrse@mail.ru`. Если хочешь более понятный адрес (его увидят пользователи), скажи, поменяю везде.

## Шаг 8. Карточка приложения в App Store Connect

[Apps](https://appstoreconnect.apple.com/apps) -> "+" -> **New App**:
- Platforms: **iOS**
- Name: `ZenHab: Habit Tracker` (имя должно быть уникальным во всём App Store; если занято, попробуй `ZenHab: Habits & Routine`)
- Primary Language: **English (U.S.)**. Он показывается во всех странах, для которых нет своего перевода
- Bundle ID: `com.baturinigor.zenhab`
- SKU: `zenhab-ios` (видишь только ты)
- User Access: Full Access

После создания открой App Information и скопируй **Apple ID** (число вроде 6740000000). Пришли его мне: впишу в `AppInfo.appStoreID`, чтобы в приложении заработала кнопка "Оценить".

## Шаг 9. Договор, банк и налоги

App Store Connect -> **Business**:
1. Free Apps Agreement принимается автоматически.
2. **Paid Apps Agreement**: без него не будут работать подписки. Заполни банковский счёт (на имя владельца аккаунта) и налоговую форму **W-8BEN** (физлицо не из США). Part II про налоговое соглашение со страной можно оставить пустым: тогда Apple удерживает налог с продаж в США по полной ставке, на остальные страны это не влияет. Российские банки Apple выплаты не принимает, нужен счёт в банке другой страны.
3. Пока статус не станет **Active**, приложение можно выпустить, но покупки в нём не загрузятся.

## Шаг 10. Покупки Pro

По [in-app-purchases.md](in-app-purchases.md): группа подписок `ZenHab Pro`, подписки на месяц и год, покупка навсегда. ID должны начинаться с твоего bundle ID.

## Шаг 11. Первая сборка

1. Слей этот PR в main.
2. GitHub -> **Actions** -> **App Store** -> Run workflow. Версия `1.0`, "Загрузить в App Store Connect" включено.
3. Сборка идёт 15-25 минут. Если упадёт, в логе будет понятная ошибка (например, какой секрет не задан или на какой ID выписан профиль). Пришли ссылку на запуск, разберусь.
4. Через 10-30 минут после успешной загрузки сборка появится в App Store Connect -> **TestFlight**. Вопрос про шифрование не появится: ответ уже в Info.plist.

Номер сборки берётся из номера запуска workflow и растёт сам. Для следующей версии укажи при запуске `1.1` и т. д.

С Mac можно и так: `xcodegen generate`, открыть проект, выбрать команду в Signing & Capabilities, Product -> Archive -> Distribute App -> App Store Connect. Тогда шаги 3-6 не нужны, но перед этим запусти `tools/appstore/set_bundle_id.sh com.baturinigor.zenhab` и не коммить получившиеся изменения.

## Шаг 12. TestFlight

1. TestFlight -> Internal Testing -> "+" группа -> добавь себя -> выбери сборку.
2. Поставь приложение **TestFlight** на iPhone и установи ZenHab оттуда.
3. Проверь: онбординг, создание привычки, напоминание и кнопки в уведомлении, виджеты на экране Домой и блокировки (тут важнее всего: App Group теперь другой), питомец, слова, экспорт и импорт.
4. Покупки в TestFlight идут в песочнице без списания денег. Купи подписку, проверь "Восстановить покупки".
5. Сделай скриншот экрана Pro с ценами: он нужен для ревью покупок.

Внутреннее тестирование (до 100 человек из твоей команды) не требует проверки Apple. Внешнее (по ссылке, до 10 000 человек) требует короткой проверки первой сборки.

## Шаг 13. Страница версии

App Store Connect -> приложение -> **iOS App 1.0**. Для каждого языка (переключатель справа сверху, "+" чтобы добавить язык) заполни из `metadata/<язык>.md`:
- Screenshots (iPhone 6.9"), см. [screenshots/README.md](screenshots/README.md)
- Promotional Text, Description, Keywords
- Support URL и Marketing URL из шага 7

Общие поля версии:
- Version: `1.0`
- Copyright: `2026 Igor Baturin`
- **Build**: "+" -> выбери загруженную сборку
- **In-App Purchases and Subscriptions**: "+" -> отметь все три товара
- **App Review Information**: из [review-notes.md](review-notes.md)
- **Version Release**: лучше **Manually release this version**, чтобы выпустить в удобный момент

Раздел **App Information** (слева): Name и Subtitle по языкам из `metadata/`, категория, Content Rights, Age Rating. Раздел **App Privacy**: ответы из [privacy-and-rating.md](privacy-and-rating.md). Раздел **Pricing and Availability**: Free, страны.

Языки для App Store: en-US и ru минимум, тексты для остальных 12 тоже готовы. Коды в App Store Connect: English (U.S.), Russian, German, French, Spanish (Spain), Portuguese (Brazil), Italian, Turkish, Polish, Indonesian, Chinese (Simplified), Japanese, Korean, Hindi.

## Шаг 14. Отправка на проверку

**Add for Review** -> **Submit to App Review**. Обычно проверка занимает от нескольких часов до 2 дней. Статусы приходят на почту и в приложение App Store Connect на iPhone. Если откажут, текст причины будет в Resolution Center: пришли его, исправим.

После одобрения нажми **Release This Version**. В поиске App Store приложение появится через несколько часов.

## Обновления

1. Слить изменения в main (SideStore-сборка соберётся как раньше).
2. Actions -> App Store -> Run workflow с новой версией (`1.1`).
3. В App Store Connect: "+" рядом с iOS App -> новая версия -> "What's New" -> выбрать сборку -> отправить.

## Что нужно сделать раз в год

- Продлить Apple Developer Program ($99), иначе приложение пропадёт из магазина.
- Перевыпустить сертификат (шаг 3) и оба профиля (шаг 4), обновить секреты `DIST_CERT_P12`, `DIST_CERT_PASSWORD`, `PROFILE_APP`, `PROFILE_WIDGET`. Уже установленные у пользователей копии продолжат работать.
