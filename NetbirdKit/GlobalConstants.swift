//
//  GlobalConstants.swift
//  NetBird
//
//  Created by Diego Romar on 03/12/25.
//

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
    /// Устаревший ключ 1.0 (14): разрешённый выход своей коробки жил в App Group
    /// UserDefaults. Расширение видело его кэш и после выключения тумблера
    /// включало выход обратно — с 1.0 (15) это файл (JetBoxSharedExit).
    static let keyJetBoxOwnExit = "jetbox.ownExit"

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

/// JetBox «только дом»: выход своей коробки, который разрешено держать
/// включённым (тумблер «All internet through my JetBox»). Пишет приложение
/// (JetBoxStore), читает сетевое расширение при каждом изменении маршрутов.
/// Файл, а не UserDefaults: UserDefaults App Group другой процесс видит из
/// своего кэша — расширение после выключения тумблера включало выход обратно
/// (баг 1.0 (14), 22.11.2026). Нет файла — расширение снимает любой выход.
enum JetBoxSharedExit {
    static let fileName = "jetbox-own-exit"

    static func defaultURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: GlobalConstants.userPreferencesSuiteName)?
            .appendingPathComponent(fileName)
    }

    static func read(at url: URL? = defaultURL()) -> String? {
        guard let url, let data = try? Data(contentsOf: url),
              let name = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return name
    }

    static func write(_ name: String?, at url: URL? = defaultURL()) {
        guard let url else { return }
        if let name, !name.isEmpty {
            try? Data(name.utf8).write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
