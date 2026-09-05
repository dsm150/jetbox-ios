# Сборка JetBox iOS (форк netbirdio/ios-client)

Форк лежит на ветке `jetbox`, поверх апстрима `netbirdio/ios-client`.
Лицензия апстрима — GPL-3.0: при **распространении** сборки (TestFlight внешним
тестерам, App Store) исходники форка обязаны быть открыты. Сборка «на свой
телефон» распространением не является. Пока ничего не распространялось.

## 0. Что нужно на машине

| Что | Версия | Проверка |
|---|---|---|
| Xcode | 26.x (проверено на 26.6) | `xcodebuild -version` |
| Go | ровно из `netbird-core/go.mod` (сейчас 1.26.7) | `go version` |
| Доступ к GitHub | **без троттлинга** | см. «Грабли» в хендовере спайка |

`xcode-select -p` должен указывать на нужный Xcode:

```bash
sudo xcode-select -s "/Applications/Xcode 2.app/Contents/Developer"
```

> ⚠️ Путь к Xcode **не должен содержать пробел**: `gomobile` кладёт вывод
> `xcrun --find clang` в `CC`, и `cgo` режет строку по пробелам
> (`cgo: C compiler "/Applications/Xcode" not found`). На этой машине Xcode
> стоит как `/Applications/Xcode 2.app`, поэтому при сборке ядра нужен либо
> симлинк без пробела, либо переустановка Xcode в обычный путь.
> Сборка **приложения** (шаг 2) пробелом не ломается — только сборка ядра.

## 1. Ядро: NetBirdSDK.xcframework

Ядро агента (Go, BSD-3, репозиторий `netbirdio/netbird`) подключено сабмодулем
`netbird-core` и собирается в xcframework скриптом апстрима:

```bash
git submodule update --init --recursive
./build-go-lib.sh          # iOS + iOS Simulator
```

Скрипт сам ставит `gomobile`/`gobind` строго той ревизии, что записана
в `netbird-core/go.mod` (`golang.org/x/mobile`), и кладёт результат в
`NetBirdSDK.xcframework/` в корне репозитория. Артефакт в git не хранится
(`.gitignore`), пересобирать нужно при каждом бампе ядра.

Тайминги на Intel iMac Pro: первый прогон ~42 мин на выкачивание Go-модулей
(1,23 ГБ) + ~13 мин компиляции; повторная сборка из кэша — 32 с.

## 2. Приложение

```bash
xcodebuild build \
  -project NetBird.xcodeproj \
  -scheme NetBird \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build
```

Тесты (в том числе разбор ссылки подключения):

```bash
xcodebuild test \
  -project NetBird.xcodeproj \
  -scheme NetBird \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build
```

Swift-package-зависимостей у форка нет: Firebase и Lottie удалены,
`xcodebuild -resolvePackageDependencies` не нужен.

## 3. Сборка на телефон (делает владелец)

Идентификаторы **уже прописаны** — руками в проекте менять ничего не нужно:

| Таргет | Bundle ID |
|---|---|
| NetBird (приложение) | `net.jet-net.jetbox` |
| NetbirdNetworkExtension | `net.jet-net.jetbox.NetworkExtension` |
| NetBirdWidgetExtensionExtension | `net.jet-net.jetbox.WidgetExtension` |
| App Group (все три) | `group.net.jet-net.jetbox` |
| Associated Domains | `applinks:box.jet-net.net` |

`DEVELOPMENT_TEAM` намеренно пустой — Team выбирает владелец.

Что завести в аккаунте Apple Developer (App ID, App Group, capabilities) —
пошагово в [../APPLE-SETUP.md](../APPLE-SETUP.md).

Порядок в Xcode:

1. Открыть `NetBird.xcodeproj`.
2. Вкладка **Signing & Capabilities** у трёх таргетов → поле **Team** → своя
   команда. Больше ничего не трогать.
3. Подключить iPhone, выбрать его в списке устройств, **Run**.
4. На телефоне: Настройки → Основные → VPN и управление устройством → доверять
   разработчику.

## 4. Проверка «одной кнопки»

Ссылка Кабинета — Universal Link, формат в
[../LINK-CONTRACT.md](../LINK-CONTRACT.md):

```
https://box.jet-net.net/connect#k=<setup-key>&m=<management-url>&e=<exit-node>&n=<имя>
```

Запасной вход той же ссылкой по своей схеме:

```
jetbox://connect#k=<setup-key>&m=<management-url>&e=<exit-node>&n=<имя>
```

Ключ и параметры лежат во **фрагменте**: не уходят на сервер при открытии,
не попадают в access-логи, Referer и историю редиректов.

В симуляторе (Universal Link там не проверить — нужен AASA на сервере и
сборка на устройство, поэтому гоняем схему; разбор у обеих ссылок общий):

```bash
xcrun simctl openurl booted \
  "jetbox://connect#k=00000000-0000-0000-0000-000000000000&m=https%3A%2F%2Fnetbird.jet-net.net&e=box-test&n=%D0%A2%D0%B5%D1%81%D1%82"
```

Смена языка и темы в симуляторе:

```bash
xcrun simctl launch booted net.jet-net.jetbox -AppleLanguages "(ru)" -AppleLocale ru_RU
xcrun simctl launch booted net.jet-net.jetbox -AppleLanguages "(en)" -AppleLocale en_US
xcrun simctl ui booted appearance dark   # / light
```

> Packet tunnel в симуляторе iOS не работает — до старта туннеля сценарий
> воспроизводится целиком, само подключение и выбор выхода проверяются только
> на живом iPhone.

## 5. Простой и расширенный режим

По умолчанию приложение в **простом режиме**: свои экраны JetBox, вкладки
NetBird (Peers, Resources, Settings с Advanced/Troubleshoot/Profiles/Change
Server) спрятаны. Флаг — `jetbox.advancedMode` в `UserDefaults.standard`.

Включается тумблером **Настройки → Расширенный режим**; обратно —
тем же тумблером в первой секции апстримового экрана Settings.

Апстримовые экраны **спрятаны, а не удалены** — иначе каждый ребейз
превращался бы в разбор конфликтов.

## 6. Правила дешёвого ребейза

1. Весь код форка — в `NetBird/Source/App/JetBox/`. Это
   **PBXFileSystemSynchronizedRootGroup**: новые файлы там подхватываются
   без правки `project.pbxproj` (главный источник конфликтов — 20 коммитов
   апстрима за полгода).
2. Врезки в апстримовые файлы держим короткими. Сейчас их четыре файла:
   - `NetBird/Source/App/NetBirdApp.swift` — `@StateObject jetbox`,
     `.environmentObject`, `handleIncomingURL`, два `.onContinueUserActivity`;
   - `NetBird/Source/App/Views/MainView.swift` — флаг простого режима,
     `JetBoxHomeView`, оверлей `JetBoxFlowView`;
   - `NetBird/Source/App/Views/iOS/iOSSettingsView.swift` — одна строка
     `JetBoxAdvancedModeSection`;
   - `NetBird/Info.plist` — схема `jetbox`.
3. **Типы и файлы `NetBird` не переименовывать.** Бренд живёт в ассетах,
   Info.plist и каталоге строк.
4. Ребейзить **на теги** апстрима, не на `main`: между тегами апстрим ломает
   себе сборку.
5. Пин ядра брать тот же, что у апстрима в `netbird-core`, и не отставать —
   иначе бинарный API `NetBirdSDK` разъедется со Swift-кодом.
6. Апстримовые имена ассетов сохранены (`netbird-logo-menu`,
   `logo-onboarding`, `icon-netbird-button`) — заменено только содержимое.
