# Макеты экранов

Макеты снимаются из кода: каталог экранов `Habits/App/DesignGallery.swift`, снимки делает
`HabitsUITests/DesignCatalogUITests.swift` через workflow **Design screens** (`.github/workflows/design.yml`).
iPhone 6.9", светлая и тёмная тема, демо-данные.

## Правило с 1.7: только новые и изменённые экраны

В `design/<версия>/screens` лежат снимки только тех экранов, которые в этой версии появились или поменялись.
Всё остальное берётся из прошлых версий: последний полный каталог — `design/1.6/screens`.

Список снимков версии — `design/<версия>/screens.txt`: по одному имени снимка из `DesignCatalogUITests.shots` (или префикс со звёздочкой, `health-*`)
на строку, после `#` можно писать комментарий. Пустой список означает, что UI в версии не меняется и снимать нечего.

## Как снять

* **В PR** workflow берёт список из `design/<версия>/screens.txt` и коммитит снимки в `design/<версия>/screens`.
* **Вручную** (Actions → Design screens → Run workflow): вход `screens` — имена через запятую или `all`
  для полного каталога. Пустой вход — список из `screens.txt`.
* **Локально:**

  ```sh
  xcodegen generate
  TEST_RUNNER_DESIGN_DIR=$PWD/design-screens TEST_RUNNER_DESIGN_LANG=ru \
  TEST_RUNNER_DESIGN_SCREENS=10-onboarding,36-paywall \
  xcodebuild test -project Habits.xcodeproj -scheme Habits \
    -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
    -only-testing:HabitsUITests/DesignCatalogUITests
  ```

Неизвестное имя в списке роняет тест, чтобы опечатка не прошла незамеченной.

## Новый экран

1. Добавить экран в `DesignGallery.swift` (`-design-screen <id>`).
2. Добавить снимок в `DesignCatalogUITests.shots` со следующим свободным номером.
3. Вписать его имя в `design/<версия>/screens.txt`.
