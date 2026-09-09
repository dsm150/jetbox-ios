import SwiftUI
import NetworkExtension
import WidgetKit

extension Color {
    // JetBox: фирменный синий #1288E1 — тот же, что у AccentColor приложения.
    // Апстримовый оранжевый (#F68330) в форке не используется нигде.
    static let jetboxBlue = Color(red: 0x12/255, green: 0x88/255, blue: 0xE1/255)
}

enum WidgetVPNStatus: String {
    case connected
    case connecting
    case disconnecting
    case disconnected

    /// Текст берётся через String(localized:), а не литералом: он уходит и в
    /// Text(...), и в реплики интентов, а Text(String) сам ничего не переводит.
    var displayText: String {
        switch self {
        case .connected: return String(localized: "Подключено")
        case .connecting: return String(localized: "Подключаем…")
        case .disconnecting: return String(localized: "Отключаем…")
        case .disconnected: return String(localized: "Отключено")
        }
    }

    var isTransitioning: Bool {
        self == .connecting || self == .disconnecting
    }

    var isStable: Bool {
        !isTransitioning
    }

    var statusColor: Color {
        switch self {
        case .connected: return .green
        case .connecting, .disconnecting: return .jetboxBlue
        case .disconnected: return Color(.systemGray3)
        }
    }

    init(neStatus: NEVPNStatus) {
        switch neStatus {
        case .connected: self = .connected
        case .connecting, .reasserting: self = .connecting
        case .disconnecting: self = .disconnecting
        case .disconnected, .invalid: self = .disconnected
        @unknown default: self = .disconnected
        }
    }
}

struct VPNStatusEntry: TimelineEntry {
    let date: Date
    let status: WidgetVPNStatus
    let ip: String
    let fqdn: String
    let needsAppSetup: Bool
    let loginRequired: Bool
    /// True when NE was mid-transition at load time (shown status is stale).
    /// Used by the timeline provider to schedule a short-interval refresh.
    var neWasTransitioning: Bool = false

    var isConnected: Bool { status == .connected }

    /// Deep-link URL for the pre-iOS 17 `Link` fallback.
    /// Mirrors the routing logic in `WidgetActionButton` so both paths stay in sync.
    /// Returns `nil` when a transitioning state makes any tap meaningless.
    var fallbackDeepLink: URL? {
        guard !status.isTransitioning else { return nil }
        if needsAppSetup && !isConnected {
            return loginRequired ? WidgetConstants.deepLinkLogin : WidgetConstants.deepLinkConnect
        }
        return isConnected ? WidgetConstants.deepLinkDisconnect : WidgetConstants.deepLinkConnect
    }
}
