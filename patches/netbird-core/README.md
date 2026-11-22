# Патчи ядра NetBird для JetBox iOS

Ядро (`netbird-core`, BSD-3-Clause) — сабмодуль на `netbirdio/netbird`; в
репозитории форка мы его не копируем. Если ядру нужна правка, она лежит
здесь патчем и накладывается перед `build-go-lib.sh`. Каждый патч — с
предложением в апстрим: как только NetBird его примет и мы сдвинем пин,
патч удаляется.

| Патч | Что | Апстрим |
|---|---|---|
| `0001-ios-refresh-wireguard-stats.patch` | `GetStatusDetails` в iOS SDK обновляет счётчики WireGuard перед выдачей статуса — иначе трафик пиров всегда 0. Та же строка, что в Android `PeersList` и в демоне ПК. | PR готовится (см. `JetBox_iOS/docs/netbird-pr-ios-wg-stats.md`), отправка — по слову владельца |
| `0002-no-netbird-cloud-defaults.patch` | `DefaultManagementURL`/`DefaultAdminURL` пустые: конфиг без адреса сервера — ошибка «management URL is not set», а не регистрация в облаке NetBird; AdminURL — от адреса management; миграция со старого облака (wiretrustee) выключена. Падают тесты апстрима `profilemanager`, которые рассчитывают на адрес по умолчанию, — ожидаемо. | Не предлагается: поведение только для JetBox (1.0 (18), решение руководителя 22.11.2026) |
| `0003-disable-relay-env.patch` | Переменная `NB_DISABLE_RELAY=true`: ядро не подключается к relay-серверам (адреса от сервера управления и из `NB_HOME_RELAY_SERVERS` отбрасываются при входе и при каждом обновлении конфига), отбрасывает TURN, ICE не собирает relay-кандидатов, `NB_FORCE_RELAY` не действует. STUN остаётся — для прямого соединения. Тесты в патче: `engine_relay_disabled_test.go`, `peer/ice/relay_disabled_test.go`. Приложение ставит переменную только в сборке США. | Не предлагается: этап 1 JetBox США (решение руководителя 23.11.2026), relay вернётся на этапе 2 |

Наложить:

```bash
for p in patches/netbird-core/*.patch; do patch -d netbird-core -p1 < "$p"; done
```

Версия ядра в сборке с патчами — с суффиксом `.jetbox<N>`
(`0.78.0+cb7ca8e.jetbox1`), чтобы на сервере управления было видно, что это
не чистое ядро апстрима.
