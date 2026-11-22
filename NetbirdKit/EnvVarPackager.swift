//
//  EnvVarPackager.swift
//  NetBird
//
//  Created by Diego Romar on 03/12/25.
//

import Foundation
import NetBirdSDK

class EnvVarPackager {
    /// Разрешённый выход, с которым последний раз запускался клиент ядра
    /// (в процессе расширения). nil — ещё не запускался.
    static var lastAllowedExit: String?
    /// Адрес пира коробки, с которым последний раз запускался клиент ядра.
    static var lastAllowedPeer: String?

    static func getEnvironmentVariables(defaults: UserDefaults) -> NetBirdSDKEnvList? {
        guard let envList = NetBirdSDKEnvList() else {
            return nil
        }

        #if os(iOS)
        let defaultForceRelay = true
        #else
        // Forced relay battery optimization not needed on Apple TV
        let defaultForceRelay = false
        #endif

        #if JETBOX_US
        // JetBox, сборка США: relay — только когда не вышло напрямую (P2P).
        // Принудительного relay нет и переключателя тоже — значение с прежних
        // сборок (там по умолчанию было true) не читаем.
        _ = defaultForceRelay
        let forceRelayConnection = false
        #else
        defaults.register(defaults: [GlobalConstants.keyForceRelayConnection: defaultForceRelay])
        let forceRelayConnection = defaults.bool(forKey: GlobalConstants.keyForceRelayConnection)
        #endif

        envList.put(NetBirdSDKGetEnvKeyNBForceRelay(), value: String(forceRelayConnection))
        #if JETBOX_US
        // JetBox, сборка США, этап 1: relay выключен в ядре (патч 0003). Ни к
        // relay, ни к TURN клиент не подключается, даже если сервер пришлёт их
        // адреса; соединение с JetBox — только напрямую, P2P через STUN.
        envList.put(NetBirdSDKGetEnvKeyNBDisableRelay(), value: "true")
        // Сборка 1.0 (20): ядро пропускает 0.0.0.0/0 и ::/0 только с этим
        // именем выхода (патч 0004) — чужой выход отбрасывается ещё до туннеля.
        // Пусто — ни одного маршрута по умолчанию.
        let allowedExit = JetBoxAllowedExit.read()
        envList.put(NetBirdSDKGetEnvKeyNBAllowedExit(), value: allowedExit)
        lastAllowedExit = allowedExit
        // 1.0 (21): только пир своей коробки (по mesh-адресу) и только его
        // маршруты (патч 0004). Пусто — ни одного удалённого пира.
        let allowedPeer = JetBoxAllowedPeer.read()
        envList.put(NetBirdSDKGetEnvKeyNBAllowedPeerIP(), value: allowedPeer)
        lastAllowedPeer = allowedPeer
        #endif
        // JetBox: метрики ядра на ingest.netbird.io не отправляем никогда —
        // переменная окружения главнее настройки сервера управления.
        envList.put("NB_METRICS_PUSH_ENABLED", value: "false")

        return envList
    }
}
