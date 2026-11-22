//
//  EnvVarPackager.swift
//  NetBird
//
//  Created by Diego Romar on 03/12/25.
//

import Foundation
import NetBirdSDK

class EnvVarPackager {
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

        return envList
    }
}
