//
//  GlobalConstants.swift
//  NetBird
//
//  Created by Diego Romar on 03/12/25.
//

import Foundation

struct GlobalConstants {
    #if os(tvOS)
    static let userPreferencesSuiteName = "group.net.jetnet.jetbox.tv"
    #else
    static let userPreferencesSuiteName = "group.net.jetnet.jetbox"
    #endif

    static let keyForceRelayConnection = "isConnectionForceRelayed"
    static let keyLoginRequired = "netbird.loginRequired"
    static let keyNetworkUnavailable = "netbird.networkUnavailable"
    static let keyConnectOnDemand = "netbird.connectOnDemand"
    static let keyOnDemandWiFiPolicy = "netbird.onDemand.wifiPolicy"
    static let keyOnDemandCellularPolicy = "netbird.onDemand.cellularPolicy"
    static let keyOnDemandWiFiNetworks = "netbird.onDemand.wifiNetworks"
    static let keyKnownSSIDs = "netbird.knownSSIDs"

    // Widget shared state keys
    static let keyWidgetVPNStatus = "netbird.widget.vpnStatus"
    static let keyWidgetIP = "netbird.widget.ip"
    static let keyWidgetFQDN = "netbird.widget.fqdn"
    // Active profile paths stored by the main app so the widget intent can
    // start the tunnel without the main app running (mirrors WidgetConstants).
    static let keyWidgetActiveConfigPath = "netbird.widget.activeConfigPath"
    static let keyWidgetActiveStatePath  = "netbird.widget.activeStatePath"

    /// startVPNTunnel(options:) key. Set by the main app when it has just verified the
    /// login state itself (its own isLoginRequired() check, or a login it just completed),
    /// letting the extension skip its duplicate check — each such check is a full Login RPC
    /// against the management server. Absent for starts the main app did not initiate
    /// (On Demand, widget intent), where the extension must still verify.
    static let optionLoginVerified = "loginVerified"

    static let configFileName = "netbird.cfg"
    static let stateFileName = "state.json"
    static let serverURLFileName = "netbird_server_url"

    /// Set by the extension when an MDM policy change triggered an engine
    /// restart; the main app clears it and tells the user the configuration
    /// was updated by their IT policy.
    static let keyMDMPolicyApplied = "netbird.mdm.policyApplied"

    /// App Group copy of the managed configuration, written by the app.
    ///
    /// iOS delivers `com.apple.configuration.managed` to the managed app's own
    /// preferences domain only. The network extension runs as a separate bundle
    /// with a separate domain and never receives it, so the app mirrors the
    /// dictionary here and the extension reads it back.
    static let keyMDMManagedConfigMirror = "netbird.mdm.managedConfigMirror"

    /// Darwin notification posted by the app whenever that mirror changes.
    /// UserDefaults.didChangeNotification is process-local and cannot tell a
    /// running extension anything; this crosses the process boundary.
    static let darwinNotificationMDMPolicyChanged = "io.netbird.mdm.policyChanged"

    /// Darwin notification posted by the network extension whenever the core's
    /// network map moves: a sync was applied, a route gained or lost its routing
    /// peer, a peer's connection state flipped. The routes only exist in the
    /// extension process, and the app's read on `.connected` lands before the
    /// first network map has arrived, so without this the app would never learn
    /// that there is something to re-read. Carries no payload; the app answers
    /// it with a GetRoutes round-trip.
    static let darwinNotificationNetworkMapChanged = "io.netbird.networkMapChanged"

    // Local notification identifiers
    static let notificationLoginRequired = "netbird.login.required"
    static let notificationMDMPolicyApplied = "netbird.mdm.policyApplied"
}

/// JetBox: стоит ли маршрут по умолчанию (0.0.0.0/0) в последних ПРИМЕНЁННЫХ
/// настройках туннеля iOS. Пишет сетевое расширение после успешного
/// setTunnelNetworkSettings, читает приложение: «Protected by your JetBox» —
/// только когда интернет правда идёт через дом (баг 1.0 (16), 22.11.2026).
/// Файл, а не UserDefaults App Group: другой процесс видит UserDefaults из кэша.
enum JetBoxTunnelState {
    static let fileName = "jetbox-tunnel-default-route"

    static func defaultURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: GlobalConstants.userPreferencesSuiteName)?
            .appendingPathComponent(fileName)
    }

    static func write(defaultRouteInTunnel: Bool, at url: URL? = defaultURL()) {
        guard let url else { return }
        try? Data((defaultRouteInTunnel ? "1" : "0").utf8).write(to: url, options: .atomic)
    }

    static func defaultRouteInTunnel(at url: URL? = defaultURL()) -> Bool {
        guard let url, let data = try? Data(contentsOf: url) else { return false }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }
}

/// JetBox, сборка США: единственный выход, через который ядро может пустить
/// весь интернет (`NB_ALLOWED_EXIT`, патч ядра 0004). Приложение пишет `e` своей
/// коробки файлом в контейнер App Group — синхронно, при сохранении коробки и
/// при запуске; расширение читает его при каждом старте клиента ядра. Файл, а
/// не UserDefaults App Group: их расширение видит с опозданием (баг 1.0 (14)).
/// Нет файла или он пуст — пустая строка: ядро не пропустит ни одного 0.0.0.0/0.
enum JetBoxAllowedExit {
    static let fileName = "jetbox-allowed-exit"
    /// Сообщение расширению: файл выхода или пира изменился, перезапусти клиента ядра.
    static let changedMessage = "JetBoxAllowedExitChanged"

    static func defaultURL() -> URL? { JetBoxCorePinFile.url(fileName) }
    static func read(at url: URL? = defaultURL()) -> String { JetBoxCorePinFile.read(at: url) }
    @discardableResult
    static func write(_ exit: String?, at url: URL? = defaultURL()) -> Bool { JetBoxCorePinFile.write(exit, at: url) }
}

/// JetBox, сборка США, 1.0 (21): mesh-адрес пира своей коробки (`box_ip` из
/// verify). Ядро говорит только с этим пиром и принимает маршруты только от
/// него (`NB_ALLOWED_PEER_IP`, патч 0004). Тот же путь, что у выхода: файл в
/// App Group, пишется синхронно до первого Connect. Нет файла — ни одного пира.
enum JetBoxAllowedPeer {
    static let fileName = "jetbox-allowed-peer-ip"

    static func defaultURL() -> URL? { JetBoxCorePinFile.url(fileName) }
    static func read(at url: URL? = defaultURL()) -> String { JetBoxCorePinFile.read(at: url) }
    @discardableResult
    static func write(_ ip: String?, at url: URL? = defaultURL()) -> Bool { JetBoxCorePinFile.write(ip, at: url) }
}

/// Маленький текстовый файл в контейнере App Group для ядра.
enum JetBoxCorePinFile {
    static func url(_ name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: GlobalConstants.userPreferencesSuiteName)?
            .appendingPathComponent(name)
    }

    static func read(at url: URL?) -> String {
        guard let url, let data = try? Data(contentsOf: url) else { return "" }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Записывает значение (nil или пусто — убирает файл). true — если изменилось.
    @discardableResult
    static func write(_ raw: String?, at url: URL?) -> Bool {
        guard let url else { return false }
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard value != read(at: url) || (value.isEmpty && FileManager.default.fileExists(atPath: url.path)) else {
            return false
        }
        if value.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            try? Data(value.utf8).write(to: url, options: .atomic)
        }
        return true
    }
}

/// JetBox: адреса серверов. Значения — из Info.plist, а туда из
/// `Config/JetBoxEdition.xcconfig` по редакции (США / русская): в коде адресов
/// нет, в бинарник сборки США чужие адреса не попадают.
enum JetBoxServers {
    /// Management NetBird по умолчанию (`https://…`).
    static var managementURL: String {
        #if os(tvOS)
        // tvOS-таргет апстрима адресов JetBox не знает.
        return "https://api.netbird.io"
        #else
        return value("JetBoxManagementURL")
        #endif
    }
    /// Маска management для `m` из ссылки Кабинета (`.домен`).
    static var managementSuffix: String { value("JetBoxManagementSuffix") }
    /// API приложения: вход по email, удаление аккаунта.
    static var apiBaseURL: String { value("JetBoxAPIBaseURL") }
    /// Хост универсальной ссылки подключения (`/connect#k=…`).
    static var connectLinkHost: String { value("JetBoxConnectLinkHost") }
    /// Хост ссылки входа из письма (`/auth/verify#t=…`).
    static var loginLinkHost: String { value("JetBoxLoginLinkHost") }
    /// Имя для проверки DNS коробки.
    static var probeName: String { value("JetBoxProbeName") }

    /// Пусто, если ключа нет или настройка сборки не подставилась: тогда
    /// подключение честно не сработает, а не уйдёт на сервер по умолчанию.
    static func value(_ key: String, bundle: Bundle = .main) -> String {
        let raw = (bundle.object(forInfoDictionaryKey: key) as? String ?? "").trimmingCharacters(in: .whitespaces)
        return raw.contains("$(") ? "" : raw
    }
}
