# Сборка JetBox iOS (форк netbirdio/ios-client)

Форк лежит на ветке `jetbox`, поверх апстрима `netbirdio/ios-client`.
Лицензия апстрима — GPL-3.0: при **распространении** сборки (TestFlight внешним
тестерам, App Store) исходники форка обязаны быть открыты. Сборка «на свой
телефон» распространением не является. Пока ничего не распространялось.

## 0. Что нужно на машине

| Что | Версия | Проверка |
|---|---|---|
| Xcode | 26.x (проверено на 26.6) | `xcodebuild -version` |
| Go | не ниже `go` из `netbird-core/go.mod` (сейчас 1.26.0; на маке 1.27.1) | `go version` |
| Доступ к GitHub | желательно без троттлинга; ядро можно брать с proxy.golang.org (§1) | см. «Грабли» в хендовере спайка |

`xcode-select -p` должен указывать на нужный Xcode:

```bash
sudo xcode-select -s "/Applications/Xcode 2.app/Contents/Developer"
```

> ⚠️ Путь к Xcode **не должен содержать пробел**: `gomobile` кладёт вывод
> `xcrun --find clang` в `CC`, и `cgo` режет строку по пробелам
> (`cgo: C compiler "/Applications/Xcode" not found`). На этой машине Xcode
> стоит как `/Applications/Xcode 2.app`; обход без sudo и переустановки —
> прокладка `xcrun` (§1, «На iMac владельца»).
> Сборка **приложения** (шаг 2) пробелом не ломается — только сборка ядра.

## 1. Ядро: NetBirdSDK.xcframework

Ядро агента (Go, BSD-3, репозиторий `netbirdio/netbird`) подключено сабмодулем
`netbird-core` и собирается в xcframework скриптом апстрима `build-go-lib.sh`.
Артефакт в git не хранится (`.gitignore`) и пересобирается **при каждом сдвиге
пина** `netbird-core` — без этого новый Swift-код апстрима не соберётся.

### Обычный путь (машина без особенностей)

```bash
git submodule update --init --recursive
./build-go-lib.sh 0.78.0+cb7ca8e      # iOS + iOS Simulator
```

### На iMac владельца (проверено 24.10.2026, ядро cb7ca8e — 4 мин)

Два препятствия и как они обходятся:

1. **GitHub троттлится** — исходник ядра берём модульным zip с
   proxy.golang.org (~30 с), а не клоном сабмодуля:
   ```bash
   mkdir -p /tmp/coredl && cd /tmp/coredl && go mod init coredl
   go mod download -json github.com/netbirdio/netbird@<полный sha из git ls-tree HEAD netbird-core>
   # → "Dir": ~/go/pkg/mod/github.com/netbirdio/netbird@v…-<sha12>
   cd -; rm -rf netbird-core && mkdir netbird-core
   rsync -a ~/go/pkg/mod/github.com/netbirdio/netbird@v…-<sha12>/ netbird-core/
   chmod -R u+w netbird-core
   ```
2. **Xcode лежит в пути с пробелом** (`/Applications/Xcode 2.app`): gomobile
   кладёт вывод `xcrun` в `CC`/`CGO_CFLAGS`, cgo режет по пробелам. Обход —
   прокладка `~/.config/jetbox-ios/xcrun-shim/xcrun`, которая подменяет путь на
   симлинк `~/XcodeNoSpace.app`. `DEVELOPER_DIR` на симлинк **не помогает** —
   `xcrun` разворачивает симлинк обратно.
   ```bash
   PATH=~/.config/jetbox-ios/xcrun-shim:$PATH ./build-go-lib.sh 0.78.0+cb7ca8e
   ```

### Какую версию передавать

Аргумент `build-go-lib.sh` — строка, которую пир сообщает серверу управления.
Правило апстрима (с #239): `<последний стабильный тег ядра на ветке>+<sha7>`.
Без аргумента локальная сборка получит `dev-<sha>` — так в магазин не отдаём.
Последний стабильный тег **на родословной** коммита, а не самый свежий:
теги v0.78.1/v0.78.2/v0.79.0 живут на релизных ветках. Проверка — GitHub API
`compare/<тег>...<sha>`: нужен статус `ahead`.

| Пин ядра | Версия | Где |
|---|---|---|
| `23a1487` | — (собрано 05.09 без аргумента) | 1.0 (1) |
| `cb7ca8e` | `0.78.0+cb7ca8e` | 1.0 (2), апстрим v0.4.1 |

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

## 4a. Релизная сборка и OTA (без Xcode у телефона)

Версия всех таргетов — **1.0**, сборка растёт на каждую загрузку в
App Store Connect: 1.0 (1) — 10.09.2026, 1.0 (2) — 24.10.2026 (апстрим
v0.4.1+). Поднимать `CURRENT_PROJECT_VERSION` **сразу во всех таргетах**
(`sed -i '' 's/CURRENT_PROJECT_VERSION = N;/CURRENT_PROJECT_VERSION = N+1;/g'`) —
Apple требует совпадения версий у расширений с приложением.

Архив подписывается облачной подписью по ASC-ключу (`~/.config/jetbox-ios/`),
физический Xcode у телефона не нужен:

```bash
xcodebuild -project NetBird.xcodeproj -scheme NetBird \
  -destination 'generic/platform=iOS' -archivePath build/JetBox.xcarchive archive \
  DEVELOPMENT_TEAM=$(cat ~/.config/jetbox-ios/asc.team) -allowProvisioningUpdates \
  -authenticationKeyPath ~/.config/jetbox-ios/asc.p8 \
  -authenticationKeyID $(cat ~/.config/jetbox-ios/asc.keyid) \
  -authenticationKeyIssuerID $(cat ~/.config/jetbox-ios/asc.issuer)

xcodebuild -exportArchive -archivePath build/JetBox.xcarchive \
  -exportPath build/export -exportOptionsPlist build/ExportOptions.plist \
  -allowProvisioningUpdates -authenticationKeyPath … -authenticationKeyID … \
  -authenticationKeyIssuerID …
```

Для **App Store / TestFlight** — `build/ExportOptions-appstore.plist`:
`method=app-store`, `uploadSymbols=false`, `destination=export`, `teamID` из
`asc.team` (с `app-store-connect` + `uploadSymbols` экспорт падает «Copy
failed»). Дальше проверка и загрузка ключом ASC (altool ищет ключ в
`~/.appstoreconnect/private_keys/AuthKey_<KID>.p8`):

```bash
KID=$(cat ~/.config/jetbox-ios/asc.keyid); ISS=$(cat ~/.config/jetbox-ios/asc.issuer)
xcrun altool --validate-app -f build/export-appstore-N/NetBird.ipa -t ios --apiKey $KID --apiIssuer $ISS
xcrun altool --upload-app   -f build/export-appstore-N/NetBird.ipa -t ios --apiKey $KID --apiIssuer $ISS
```

Сборка обрабатывается 5–30 мин, потом её надо **привязать к версии** в ASC
(`PATCH /v1/appStoreVersions/<id>/relationships/build`) и выдать группе
TestFlight «Владелец».

`method=debugging` — сборка для устройств, зарегистрированных в аккаунте.
Finder перетаскиванием `.ipa` **не ставит**: раздача только OTA — `manifest.plist`
плюс страница с `itms-services://` на https (кладётся во временный каталог
`app/static/<случайное имя>/` Кабинета и снимается после проверки).

## 5. Простой и расширенный режим

По умолчанию приложение в **простом режиме**: свои экраны JetBox, вкладки
NetBird (Peers, Resources, Settings с Advanced/Troubleshoot/Profiles/Change
Server) спрятаны. Флаг — `jetbox.advancedMode` в `UserDefaults.standard`.

Включается тумблером **Настройки → Расширенный режим**; обратно —
тем же тумблером в первой секции апстримового экрана Settings.

Апстримовые экраны **спрятаны, а не удалены** — иначе каждый ребейз
превращался бы в разбор конфликтов.

## 6. Как не отставать от апстрима

Форк живёт поверх `netbirdio/ios-client`. Апстрим выпускает тег примерно раз
в 2–4 недели (v0.3.0 → v0.4.1 за июль–сентябрь 2026), и каждый тег — это
исправления туннеля, которые клиент JetBox получает только через нас.

### 6.1. Правило

* **Сливаем (`merge`), а не ребейзим.** `main` публичного репозитория — это
  наша `jetbox`; ребейз переписал бы опубликованную историю (force-push,
  битые ссылки на коммиты в NOTICE, хендоверах и у тех, кто склонировал).
  Каждое обновление — один merge-коммит с тегом апстрима во втором родителе
  и разбором конфликтов в сообщении.
* **Цель — тег апстрима.** Между тегами апстрим бывает несобираемым.
  Коммиты после тега берём отдельным вторым merge, только если они чинят то,
  что видно у нас (пример: #243 — старт из Пункта управления после другого VPN).
* **Срок — неделя от выхода тега**, исправления безопасности ядра — сразу.
* **Своя версия.** `MARKETING_VERSION` у нас своя (1.0, 1.1, …), номер сборки
  растёт на каждую загрузку в App Store Connect. Какой апстрим внутри —
  пишем в «Что нового» и в хендовер, а не в номер версии.

### 6.2. Порядок одного обновления

```bash
git fetch origin --tags
git log --oneline <прошлый тег>..<новый тег>            # что пришло
git diff --name-only <прошлый тег> <новый тег> > /tmp/up.txt
git diff --name-only <прошлый тег> jetbox      > /tmp/our.txt
comm -12 /tmp/up.txt /tmp/our.txt                       # где будут конфликты
git switch -c update/upstream-<тег> jetbox
git -c merge.conflictstyle=zdiff3 merge --no-ff --no-commit <тег>
```

1. Разрешить конфликты (таблица 6.3), закоммитить с разбором.
2. Если сдвинулся пин `netbird-core` — пересобрать ядро (§1). Без этого
   новый Swift-код апстрима не соберётся: он зовёт новые API `NetBirdSDK`.
3. Проверки — **все** (6.4).
4. `jetbox` ← fast-forward из ветки обновления, `git push public jetbox:main`.
5. Сборка `+1`, архив, загрузка в ASC, TestFlight владельцу (§4a).
6. На телефоне — чек-лист 6.5. Только после него — в ревью.

### 6.3. Где конфликтует и что оставлять

| Файл | Наше | Что берём у апстрима |
|---|---|---|
| `NetbirdKit/NetworkExtensionAdapter.swift` | `extensionID = net.jet-net.jetbox.NetworkExtension`, `extensionName = "JetBox"`, поиск профиля через `isOurProfile` (имя + `providerBundleIdentifier`, старое имя узнаётся) | всё остальное. ⚠️ С v0.4.1 апстрим выводит ID из бандла как `<bundle>.NetbirdNetworkExtension` — у нас суффикс другой, шаблон не подходит |
| `NetBird/Source/App/NetBirdApp.swift` | `configureFirebaseIfNeeded() {}` — пустая, Firebase в форке нет | новые точки жизненного цикла |
| `NetBird/Source/App/Views/MainView.swift` | флаг простого режима, `JetBoxHomeView`, оверлей `JetBoxFlowView`, анимация `jetbox.step` | модификаторы рядом (`onAppear` и т. п.) — обе стороны |
| `NetBird/Source/App/Views/iOS/iOSSettingsView.swift` | первой строкой `JetBoxAdvancedModeSection` | секции и гейты — обе стороны |
| `NetbirdNetworkExtension/PacketTunnelProvider.swift` | — | группа приложений через `GlobalConstants.userPreferencesSuiteName` (у нас там `group.net.jet-net.jetbox`) |
| `NetbirdKit/GlobalConstants.swift` | `group.net.jet-net.jetbox` | новые ключи |
| `NetBirdWidgetExtension/**` | русские строки, `jetbox-mark`, тинт бренда | логика интентов (обычно сливается сама) |
| `NetBird/Info.plist` | схема `jetbox`, Associated Domains | новые ключи |
| `README.md` | наш целиком | — |
| `project.pbxproj` | идентификаторы `net.jet-net.jetbox…`, версии, без фаз Crashlytics | новые файлы и таргеты; после слияния — `grep PRODUCT_BUNDLE_IDENTIFIER` |

### 6.4. Проверки после слияния

```bash
# 1. Идентификаторы апстрима не вернулись (логгеры и домены ошибок — можно)
git grep -n -E 'io\.netbird\.app|group\.io\.netbird' -- '*.plist' '*.entitlements' '*.pbxproj'
grep -oE 'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;' NetBird.xcodeproj/project.pbxproj | sort -u
# 2. Телеметрия Google не вернулась
git grep -n -E 'import Firebase|FirebaseApp\.configure|Crashlytics\.' -- '*.swift'
# 3. Секретов нет
gitleaks git --log-opts="jetbox" --redact
# 4. Тесты (в т.ч. JetBoxWordingTests, VPNProfileNamingTests, GlobalConstantsTests)
xcodebuild test -project NetBird.xcodeproj -scheme NetBird \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath build
# 5. Архив проходит валидацию магазина (§4a)
```

Новые экраны апстрима: найти, куда они встали, и убедиться, что в простом
режиме клиент их не видит (как Profiles/Change Server — за `advancedMode`).

### 6.5. Чек-лист на телефоне (TestFlight)

1. Ссылка из Кабинета → одна кнопка → «Вы под защитой», выход выбран.
2. Выключить/включить из приложения, из виджета, из Пункта управления.
3. Включить официальный NetBird (или любой VPN), затем снова JetBox из
   Пункта управления — без перелогина.
4. Перезагрузить телефон → JetBox включается без перелогина.
5. Обновление поверх прежней сборки: профиль «JetBox» на месте, повторно
   ссылку не просит.
6. Расширенные настройки — семь нажатий, выход из режима работает.

### 6.6. Правила, которые держат конфликты маленькими

1. Весь код форка — в `NetBird/Source/App/JetBox/`. Это
   **PBXFileSystemSynchronizedRootGroup**: новые файлы там подхватываются
   без правки `project.pbxproj`.
2. Врезки в апстримовые файлы — короткие, и каждая есть в таблице 6.3.
   Новая врезка = новая строка в таблице.
3. **Типы и файлы `NetBird` не переименовывать.** Бренд живёт в ассетах,
   Info.plist и каталогах строк.
4. Апстримовые экраны **прятать, а не удалять**; апстримовые workflow в
   `.github/` не трогать (Actions выключены флагом репозитория).
5. Пин ядра — тот же, что у апстрима в `netbird-core`, иначе бинарный API
   `NetBirdSDK` разъедется со Swift-кодом.
6. **У расширений свои каталоги ассетов.** `NetBirdWidgetExtension/Assets.xcassets`
   держит собственные копии `logo-onboarding`, `netbird-logo-menu` и прочего:
   ребрендинг приложения их не задевает. При смене знака проверять каждый
   каталог, а не только `NetBird/Assets.xcassets` (на этом попались 09.09 —
   в виджете оставался логотип NetBird).
7. Апстримовые имена ассетов сохранены (`netbird-logo-menu`,
   `logo-onboarding`, `icon-netbird-button`) — заменено только содержимое.
