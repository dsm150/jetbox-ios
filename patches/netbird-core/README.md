# Патчи ядра NetBird для JetBox iOS

Ядро (`netbird-core`, BSD-3-Clause) — сабмодуль на `netbirdio/netbird`; в
репозитории форка мы его не копируем. Если ядру нужна правка, она лежит
здесь патчем и накладывается перед `build-go-lib.sh`. Каждый патч — с
предложением в апстрим: как только NetBird его примет и мы сдвинем пин,
патч удаляется.

| Патч | Что | Апстрим |
|---|---|---|
| `0001-ios-refresh-wireguard-stats.patch` | `GetStatusDetails` в iOS SDK обновляет счётчики WireGuard перед выдачей статуса — иначе трафик пиров всегда 0. Та же строка, что в Android `PeersList` и в демоне ПК. | PR готовится (см. `JetBox_iOS/docs/netbird-pr-ios-wg-stats.md`), отправка — по слову владельца |

Наложить:

```bash
for p in patches/netbird-core/*.patch; do patch -d netbird-core -p1 < "$p"; done
```

Версия ядра в сборке с патчами — с суффиксом `.jetbox<N>`
(`0.78.0+cb7ca8e.jetbox1`), чтобы на сервере управления было видно, что это
не чистое ядро апстрима.
