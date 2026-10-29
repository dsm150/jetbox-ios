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
   for p in patches/netbird-core/*.patch; do patch -d netbird-core -p1 < "$p"; done
   PATH=~/.config/jetbox-ios/xcrun-shim:$PATH ./build-go-lib.sh 0.78.0+cb7ca8e.jetbox1
   ```

### Патчи ядра

`patches/netbird-core/` — правки ядра, которые нам нужны раньше, чем их примет
NetBird (описание и статус апстрима — в `README.md` там же). Накладываются
**перед** сборкой, версия получает суффикс `.jetbox<N>`. При каждом сдвиге пина
ядра: проверить, не принят ли патч апстримом (тогда удалить), и что он ложится
(`patch --dry-run`).

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
| `cb7ca8e` | `0.78.0+cb7ca8e` | 1.0 (2)–1.0 (4), апстрим v0.4.1 |
| `cb7ca8e` + `0001` | `0.78.0+cb7ca8e.jetbox1` | 1.0 (5): трафик пиров на iOS |

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
| NetBird (приложение) | `net.jetnet.jetbox` |
| NetbirdNetworkExtension | `net.jetnet.jetbox.NetworkExtension` |
| NetBirdWidgetExtensionExtension | `net.jetnet.jetbox.WidgetExtension` |
| App Group (все три) | `group.net.jetnet.jetbox` |
| Associated Domains | `applinks:box.jet-net.net` |

`DEVELOPMENT_TEAM` намеренно пустой — команда передаётся командой сборки.
С 1.0 (8) (29.10.2026) приложение живёт в команде организации **INSTASHOP
Corporation, `FRPY3A4QGK`** (ASC: приложение `6828493462`). До 1.0 (7) были
`net.jet-net.jetbox…` в команде частного лица `U2ZLMVKGQR` — Apple отклонила по
Guideline 5.4 (VPN только от организации); те ID остались в старой команде.
Миграции VPN-профиля со старого ID нет и быть не может: это другое приложение,
iOS не показывает ему чужие профили — пользователь ставит новое и открывает ссылку заново.

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
xcrun simctl launch booted net.jetnet.jetbox -AppleLanguages "(ru)" -AppleLocale ru_RU
xcrun simctl launch booted net.jetnet.jetbox -AppleLanguages "(en)" -AppleLocale en_US
xcrun simctl ui booted appearance dark   # / light
```

> Packet tunnel в симуляторе iOS не работает — до старта туннеля сценарий
> воспроизводится целиком, само подключение и выбор выхода проверяются только
> на живом iPhone.

## 4a. Релизная сборка и OTA (без Xcode у телефона)

Версия всех таргетов — **1.0**, сборка растёт на каждую загрузку в
App Store Connect: 1.0 (1) — 10.09.2026, 1.0 (2) — 24.10.2026 (апстрим
v0.4.1+), 1.0 (3) — 24.10.2026 (Liquid Glass, щит-кнопка, новая иконка), 1.0 (4) — 24.10.2026
(стеклянная панель дома, уведомления после подключения, «О программе» без NetBird),
1.0 (5) — 24.10.2026 (фирменный синий, «до дома» замером DNS, напрямую по умолчанию,
патч ядра на трафик), 1.0 (6) — 25.10.2026 (нигде не показываем «Сервер»), 1.0 (7) — 25.10.2026 (имя дома
обновляется по ссылке, лист подробностей по высоте содержимого), 1.0 (8) — 29.10.2026 (переезд
в команду `FRPY3A4QGK`, ID `net.jetnet.jetbox…`). Поднимать `CURRENT_PROJECT_VERSION` **сразу во всех таргетах**
(`sed -i '' 's/CURRENT_PROJECT_VERSION = N;/CURRENT_PROJECT_VERSION = N+1;/g'`) —
Apple требует совпадения версий у расширений с приложением.

Архив подписывается облачной подписью по ASC-ключу команды `FRPY3A4QGK`
(`~/.config/jetbox-ios-cardo/`, роль Admin; старый `~/.config/jetbox-ios/` — команда
`U2ZLMVKGQR`, для JetBox больше не нужен), физический Xcode у телефона не нужен.
Сертификат распространения — существующий «iOS Distribution: INSTASHOP Corporation»
(его ключ уже в связке ключей этого мака), профили «iOS Team Store Provisioning
Profile: net.jetnet.jetbox…» Xcode завёл сам:

```bash
K=~/.config/jetbox-ios-cardo
xcodebuild -project NetBird.xcodeproj -scheme NetBird \
  -destination 'generic/platform=iOS' -archivePath build/JetBox.xcarchive archive \
  DEVELOPMENT_TEAM=FRPY3A4QGK -allowProvisioningUpdates \
  -authenticationKeyPath $K/asc.p8 \
  -authenticationKeyID $(cat $K/asc.keyid) \
  -authenticationKeyIssuerID $(cat $K/asc.issuer)

xcodebuild -exportArchive -archivePath build/JetBox.xcarchive \
  -exportPath build/export -exportOptionsPlist build/ExportOptions.plist \
  -allowProvisioningUpdates -authenticationKeyPath … -authenticationKeyID … \
  -authenticationKeyIssuerID …
```

Для **App Store / TestFlight** — `build/ExportOptions-appstore.plist`:
`method=app-store`, `uploadSymbols=false`, `destination=export`,
`teamID=FRPY3A4QGK` (с `app-store-connect` + `uploadSymbols` экспорт падает «Copy
failed»). Дальше проверка и загрузка ключом ASC; путь к ключу — `--p8-file-path`
(в `~/.appstoreconnect/private_keys/` ключ JetBox не кладём — там чужие ключи команды):

```bash
K=~/.config/jetbox-ios-cardo; KID=$(cat $K/asc.keyid); ISS=$(cat $K/asc.issuer)
xcrun altool --validate-app -f build/export-appstore-N/NetBird.ipa -t ios --apiKey $KID --apiIssuer $ISS --p8-file-path $K/asc.p8
xcrun altool --upload-app   -f build/export-appstore-N/NetBird.ipa -t ios --apiKey $KID --apiIssuer $ISS --p8-file-path $K/asc.p8
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
Server) спрятаны. Флаги — `jetbox.advancedUnlocked` и `jetbox.advancedMode`
в App Group.

Открывается **семью быстрыми нажатиями по строке «Версия»** в настройках
JetBox (с четвёртого — «Ещё N нажатий…»), затем пункт «Расширенные
настройки». Обратно — первая строка апстримового экрана Settings
«Выключить расширенные настройки»: закрывает и режим, и доступ.

## 5a. Оформление Liquid Glass и демо щита

С 1.0 (3) экраны JetBox — в языке Liquid Glass (iOS 26): стеклянный щит-кнопка,
стеклянные капсулы и кнопка настроек, живой фон. С 1.0 (4) включает и выключает
**только щит**; внизу — стеклянная панель дома (`Views/JetBoxHomeDock.swift`:
время в сети, пинг до дома, напрямую/ретранслятор; данные — `JetBoxLiveStats`),
по нажатию — лист `JetBoxConnectionSheet` (выбор выхода — только если выходов
больше одного). На iOS 15–25 — тот же макет
с материалом `.ultraThinMaterial` и заливными капсулами. Компоненты —
`Views/JetBoxShield.swift`, `JetBoxGlass.swift`, `JetBoxBackdrop.swift`;
действие щита и кнопки — одна функция `JetBoxPowerAction` (тесты
`JetBoxPowerActionTests`). Иконка — `JetBox/AppIcon.icon` (Icon Composer),
для iOS до 26 — одноимённый `AppIcon.appiconset`. Рендер вариантов иконки:

```bash
"/Applications/Xcode 2.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  NetBird/Source/App/JetBox/AppIcon.icon --export-image --output-file /tmp/icon.png \
  --platform iOS --rendition Default --width 1024 --height 1024 --scale 1   # Dark, ClearLight, TintedDark…
```

Туннель в симуляторе не поднимается, поэтому для съёмки главного экрана есть
**DEBUG-демо** (в релизную сборку не попадает):

```bash
xcrun simctl launch <UDID> net.jetnet.jetbox -JetBoxShieldDemo                       # тап по щиту отыгрывает фазы
xcrun simctl launch <UDID> net.jetnet.jetbox -JetBoxShieldDemo -JetBoxShieldDemoState connecting   # сразу в фазе
xcrun simctl launch <UDID> net.jetnet.jetbox -JetBoxShieldDemo -JetBoxShieldDemoState connected -JetBoxShieldDemoDetails YES  # с листом подробностей
```

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
| `NetbirdKit/NetworkExtensionAdapter.swift` | `extensionID = net.jetnet.jetbox.NetworkExtension`, `extensionName = "JetBox"`, поиск профиля через `isOurProfile` (имя + `providerBundleIdentifier`, старое имя узнаётся) | всё остальное. ⚠️ С v0.4.1 апстрим выводит ID из бандла как `<bundle>.NetbirdNetworkExtension` — у нас суффикс другой, шаблон не подходит |
| `NetBird/Source/App/NetBirdApp.swift` | `configureFirebaseIfNeeded() {}` — пустая, Firebase в форке нет; в `AppDelegate` **нет** `requestAuthorization` (спрашиваем после первого подключения — `JetBoxNotifications`); в `init` — одна строка `JetBoxStartup.run()` | новые точки жизненного цикла |
| `netbird-core` (сабмодуль) | правок в дереве нет — только `patches/netbird-core/*.patch` | пин ядра |
| `NetBird/Source/App/ViewModels/MainViewModel.swift` | в `startPollingDetails` под `#if os(iOS)` — `JetBoxLiveStats.shared.ingest(details, connectedSince:)` (живые показатели панели) | всё остальное |
| `NetBird/Source/App/Views/AboutView.swift` | без «Join Beta Program» и алерта TestFlight NetBird; ссылки — `JetBoxConfig.licenseURL`/`privacyPolicyURL`; «© <год> JetNet» | новые строки экрана |
| `NetBird/Source/App/Views/MainView.swift` | флаг простого режима, `JetBoxHomeView`, оверлей `JetBoxFlowView`, анимация `jetbox.step` | модификаторы рядом (`onAppear` и т. п.) — обе стороны |
| `NetBird/Source/App/Views/iOS/iOSSettingsView.swift` | первой строкой `JetBoxAdvancedModeSection` | секции и гейты — обе стороны |
| `NetbirdNetworkExtension/PacketTunnelProvider.swift` | — | группа приложений через `GlobalConstants.userPreferencesSuiteName` (у нас там `group.net.jetnet.jetbox`) |
| `NetbirdKit/GlobalConstants.swift` | `group.net.jetnet.jetbox` | новые ключи |
| `NetBirdWidgetExtension/**` | русские строки, `jetbox-mark`, тинт бренда | логика интентов (обычно сливается сама) |
| `NetBird/Info.plist` | схема `jetbox`, Associated Domains | новые ключи |
| `README.md` | наш целиком | — |
| `project.pbxproj` | идентификаторы `net.jetnet.jetbox…`, версии, без фаз Crashlytics | новые файлы и таргеты; после слияния — `grep PRODUCT_BUNDLE_IDENTIFIER` |

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
