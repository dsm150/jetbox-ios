# Сборка JetBox iOS (форк netbirdio/ios-client)

Форк лежит на ветке `jetbox`, поверх апстрима `netbirdio/ios-client` (`main`).
Лицензия апстрима — GPL-3.0: при **распространении** сборки исходники форка
обязаны быть открыты. Пока ничего не распространялось.

## 0. Что нужно на машине

| Что | Версия | Проверка |
|---|---|---|
| Xcode | 26.x (проверено на 26.6) | `xcodebuild -version` |
| Go | ровно из `netbird-core/go.mod` (сейчас 1.26.x) | `go version` |
| Доступ к GitHub | **без троттлинга** | см. «Грабли» в хендовере |

`xcode-select -p` должен указывать на нужный Xcode:

```bash
sudo xcode-select -s "/Applications/Xcode 2.app/Contents/Developer"
```

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

## 2. Приложение

```bash
xcodebuild build \
  -project NetBird.xcodeproj \
  -scheme NetBird \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Swift-package-зависимостей у форка нет: Firebase и Lottie удалены,
`xcodebuild -resolvePackageDependencies` не нужен.

## 3. Сборка на телефон (делает владелец)

1. Открыть `NetBird.xcodeproj` в Xcode.
2. Для **каждого** таргета (`NetBird`, `NetbirdNetworkExtension`,
   `NetBirdWidgetExtensionExtension`) в *Signing & Capabilities* выбрать свою
   Team и заменить bundle identifier — `io.netbird.app*` занят NetBird,
   подписать им чужой командой нельзя. Предлагаемая схема:
   - `net.jet-net.jetbox`
   - `net.jet-net.jetbox.NetworkExtension`
   - `net.jet-net.jetbox.Widget`
3. В App Group заменить `group.io.netbird.app` на `group.net.jet-net.jetbox`
   — и в `NetBird/NetBird.entitlements`,
   `NetbirdNetworkExtension/NetbirdNetworkExtension.entitlements`,
   `NetBirdWidgetExtension/NetBirdWidgetExtension.entitlements`,
   и в `NetbirdKit/GlobalConstants.swift` (`userPreferencesSuiteName`),
   и в `NetbirdNetworkExtension/Info.plist` (ключ `FirebaseAppGroup` можно
   просто удалить — Firebase из форка убран).
4. Capability *Network Extensions → Packet Tunnel* и *App Groups* должны быть
   включены у профиля разработчика (у бесплатного Apple ID Packet Tunnel
   недоступен — нужен платный аккаунт Apple Developer Program).
5. Собрать на устройство. **Автоподпись под владельца настроена не была
   намеренно** — team выбирает владелец.

## 4. Проверка «одной кнопки»

Ссылка Кабинета:

```
jetbox://connect#k=<setup-key>[&m=<management-url>]
```

* `k` — setup key, лежит во **фрагменте**: не уходит на сервер при открытии,
  не попадает в access-логи, Referer и историю редиректов.
* `m` — необязателен; по умолчанию `https://netbird.jet-net.net`
  (константа `JetBoxDeepLink.defaultManagementURL` в
  `NetBird/Source/App/NetBirdApp.swift`).

В симуляторе:

```bash
xcrun simctl openurl booted "jetbox://connect#k=00000000-0000-0000-0000-000000000000"
```

На телефоне — открыть такую ссылку из Safari/Кабинета.

Дальше приложение показывает экран JetBox с адресом коробки, маской ключа и
единственной кнопкой «Подключить»; по нажатию — регистрация устройства по
setup key и старт туннеля, затем «Вы под защитой JetBox».

> Packet tunnel в симуляторе iOS не работает — до старта туннеля сценарий
> воспроизводится, само подключение проверяется только на живом iPhone.
