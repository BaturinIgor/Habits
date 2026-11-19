# Скрипты App Store Connect

Всё запускается вручную: Actions -> нужный workflow -> Run workflow. Репозиторий публичный,
поэтому скрипты печатают в лог только ID, статусы и HTTP-коды (без тел ответов, ключей и профилей).

Общие секреты: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (ключ App Store Connect API),
переменная `APP_BUNDLE_ID` (по умолчанию `com.baturinigor.zenhab`).
Зависимости: `pip install -r tools/appstore/requirements.txt`.

| Workflow | Скрипт | Что делает |
|---|---|---|
| App Store | — | Сборка, подпись, загрузка в App Store Connect |
| App Store texts | `asc_whats_new.py` | Создаёт версию, заполняет тексты и «Что нового», прикрепляет сборку |
| App Store provisioning | `asc_provision_watch.py` | Проверяет и создаёт bundle ID, App Groups и профили для Apple Watch (секреты не пишет) |
| App Store screenshots | `asc_screenshots.py` | Загружает скриншоты по всем языкам |
| App Store submit | `asc_submit.py` | Проверяет версию и отправляет на ревью |

Порядок выпуска версии: App Store -> App Store texts (с номером сборки) -> App Store screenshots ->
вручную App Privacy (если менялось) -> App Store submit с `confirm=yes`.

## Роль ключа API

- Профили, bundle ID и сертификаты (provisioning) требуют доступа к Certificates, Identifiers & Profiles.
  Надёжно работает ключ с ролью **Admin**. С ролью App Manager может вернуть 403: тогда нужен Admin-ключ.
- Скриншоты, тексты, отправка на ревью: **Admin** или **App Manager**.

## App Store provisioning (часы)

Скрипт `asc_provision_watch.py` (всё идемпотентно):

1. Регистрирует `<APP_ID>.watchkitapp` и `<APP_ID>.watchkitapp.widget` (платформа iOS), если их нет.
2. Включает на них capability App Groups.
3. Находит сертификат Apple Distribution: тот, что лежит в `DIST_CERT_P12`, иначе самый свежий.
4. Создаёт профили App Store «ZenHab Watch App Store» и «ZenHab Watch Widget App Store» или берёт
   существующие, если они действующие, с тем же сертификатом и с группой. Недействительные пересоздаёт.
5. Дальше по режиму:
   - `--dry-run` — ничего не меняет, показывает план;
   - `--create` — только создаёт недостающее в Apple (так работает workflow);
   - `--install` — для сборки: кладёт оба профиля в `~/Library/MobileDevice/Provisioning Profiles`
     (и в папку Xcode) под именем `<UUID>.mobileprovision` и пишет только их имена в `$GITHUB_ENV`
     (`WATCH_PROFILE_NAME`, `WATCH_WIDGET_PROFILE_NAME`) и `$GITHUB_OUTPUT`
     (`watch_profile_name`, `watch_widget_profile_name`);
   - `--out DIR` — локально записывает `.mobileprovision` в папку;
   - `--store-secrets` — по желанию и только локально: кладёт профили в секреты `PROFILE_WATCH*` через твой `gh`.

Секреты `PROFILE_WATCH` и `PROFILE_WATCH_WIDGET` и токен с правом записи секретов **не нужны**:
сборка берёт или создаёт профили сама при каждом запуске. Workflow «App Store provisioning»
нужен, чтобы заранее проверить (`dry_run`, включён по умолчанию) или создать всё в Apple.

**Ручной шаг: группа App Group.** В App Store Connect API нет способа привязать конкретную группу
к bundle ID, можно только включить capability. Поэтому первый запуск, скорее всего, закончится
предупреждением, и профиль без группы скрипт не установит. Нужно один раз для каждого из двух ID:
developer.apple.com/account/resources/identifiers -> `<APP_ID>.watchkitapp` -> App Groups ->
Configure (или Edit) -> отметить `group.<APP_ID>` -> Continue -> Save. Затем запустить workflow
ещё раз (без `dry_run`): профили пересоздадутся уже с группой.

### Подключение к сборке (appstore.yml в ветке часов)

В main таргетов часов пока нет, поэтому `appstore.yml` здесь не меняется. При слиянии ветки
`claude/project-thread-hdy2nz` шаг «Install certificate and profiles» должен ставить профили часов
из секретов, только если они заданы, а иначе брать их через API:

1. В шаге «Check secrets» убрать `PROFILE_WATCH` и `PROFILE_WATCH_WIDGET` из обязательных.
2. В `env:` шага «Install certificate and profiles» добавить:

```yaml
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          ASC_KEY_P8: ${{ secrets.ASC_KEY_P8 }}
```

   (`PROFILE_WATCH`, `PROFILE_WATCH_WIDGET`, `DIST_CERT_P12`, `DIST_CERT_PASSWORD` там уже есть.)
3. Две строки `install_profile "$PROFILE_WATCH" ...` и `install_profile "$PROFILE_WATCH_WIDGET" ...`
   заменить на:

```bash
          if [ -n "${PROFILE_WATCH:-}" ] && [ -n "${PROFILE_WATCH_WIDGET:-}" ]; then
            install_profile "$PROFILE_WATCH" "$APP_ID.watchkitapp" WATCH_PROFILE_NAME
            install_profile "$PROFILE_WATCH_WIDGET" "$APP_ID.watchkitapp.widget" WATCH_WIDGET_PROFILE_NAME
          else
            echo "Секретов PROFILE_WATCH* нет, беру профили часов через App Store Connect API"
            python3 -m venv "$RUNNER_TEMP/asc-venv"
            "$RUNNER_TEMP/asc-venv/bin/pip" install -q -r tools/appstore/requirements.txt
            APP_BUNDLE_ID="$APP_ID" "$RUNNER_TEMP/asc-venv/bin/python" tools/appstore/asc_provision_watch.py --install
          fi
```

`--install` сам пишет `WATCH_PROFILE_NAME` и `WATCH_WIDGET_PROFILE_NAME` в `$GITHUB_ENV`,
поэтому шаги Archive и Export IPA не меняются. Ключу API для этого нужна роль Admin
(см. «Роль ключа API»).

### Локальный запуск на Mac

```bash
pip3 install -r tools/appstore/requirements.txt
export ASC_KEY_ID=... ASC_ISSUER_ID=...
export ASC_KEY_P8="$(cat ~/Downloads/AuthKey_XXXX.p8)"
# необязательно, чтобы профиль был на тот же сертификат, что в секрете DIST_CERT_P12:
# export DIST_CERT_P12="$(base64 -i cert.p12)" DIST_CERT_PASSWORD=...
python3 tools/appstore/asc_provision_watch.py --dry-run                 # посмотреть план
python3 tools/appstore/asc_provision_watch.py --out ~/Desktop/watch-profiles
# по желанию: ещё и положить в секреты репозитория своим gh (нужен gh auth login)
python3 tools/appstore/asc_provision_watch.py --out ~/Desktop/watch-profiles --store-secrets
```

## App Store screenshots

Папка (`dir` в репозитории или zip по ссылке `zip_url`):

```
<dir>/en-US/01.png 02.png ...     iPhone 1320x2868 (make_screenshots.py)
<dir>/en-US/watch/01.png ...      Apple Watch, по желанию
<dir>/ru/...                      имена папок = коды языков, как в docs/appstore/metadata
```

- Тип экрана берётся из размера: 1320x2868, 1290x2796, 1260x2736 -> `APP_IPHONE_67` (в API так
  называется слот iPhone 6.9"; отдельного `APP_IPHONE_69` нет). Часы: 422x514 и 410x502 -> Ultra,
  416x496 -> Series 10, 396x484 -> Series 7, 368x448 -> Series 4.
- Набор, где уже лежат те же файлы в том же порядке (MD5), не трогается. Иначе старые скриншоты
  набора удаляются и загружаются новые.
- Языки без папки пропускаются: App Store покажет скриншоты основного языка.
- По умолчанию `dry_run` включён: только список изменений. `prune` удаляет наборы других размеров
  iPhone/часов (например, старый 6.5"), чтобы везде показывались новые.

Локально: `python3 tools/appstore/asc_screenshots.py --version 1.6 --dir appstore-shots --dry-run`.

## App Store submit

Проверяет: состояние версии, прикреплённую обработанную сборку (и ответ про шифрование),
тексты для всех 14 языков из `docs/appstore/metadata` (описание, ключевые слова, URL поддержки,
«Что нового», название, ссылка на политику), скриншоты iPhone у основного языка и что все
скриншоты обработаны. Затем создаёт (или берёт незавершённую) отправку на ревью, добавляет версию
и отправляет. Без `confirm=yes` только проверяет и завершается с ошибкой.

## Что остаётся вручную

- **App Privacy** («Конфиденциальность приложения»): публичного API нет. Ответы см. в
  `docs/appstore/privacy-and-rating.md`, опубликовать в App Store Connect -> App Privacy -> Publish.
  Скрипт отправки об этом только предупреждает.
- **Привязка App Group** к bundle ID часов (см. выше), один раз.
- Подключение `--install` к `appstore.yml` при слиянии ветки часов (сниппет выше).
- Встроенные покупки, которые отправляются впервые, выбираются на странице версии
  (In-App Purchases) — см. `docs/appstore/in-app-purchases.md`.
- Ответ про экспортное шифрование, если в сборке нет `ITSAppUsesNonExemptEncryption`.

## Тесты

```bash
python3 -m unittest discover -s tools/appstore/tests -v
```

Настоящий API не вызывается: HTTP подменён, проверяются тела запросов и решения
(переиспользовать / пересоздать / пропустить).
