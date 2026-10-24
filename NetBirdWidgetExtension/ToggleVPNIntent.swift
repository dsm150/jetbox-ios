import AppIntents
import NetworkExtension
import WidgetKit

/// Used by the widget buttons. For Siri/Shortcuts use ConnectVPNIntent or DisconnectVPNIntent.
@available(iOS 16.0, *)
struct ToggleVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "Переключить JetBox"
    static var description: IntentDescription = "Подключение и отключение JetBox."
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Действие")
    var action: String

    init() { self.action = "connect" }
    init(action: String) { self.action = action }

    func perform() async throws -> some IntentResult {
        guard let manager = try await VPNIntentHelpers.loadManager() else {
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        }

        let defaults = VPNIntentHelpers.defaults

        if action == "connect" {
            guard !VPNIntentHelpers.isLoginRequired else {
                WidgetCenter.shared.reloadAllTimelines()
                return .result()
            }
            let status = manager.connection.status
            if status == .disconnected || status == .invalid {
                try await VPNIntentHelpers.startTunnel(manager: manager)
            }
        } else {
            let neStatus = manager.connection.status
            let persistedRaw = defaults?.string(forKey: WidgetConstants.keyVPNStatus) ?? "disconnected"
            let persisted = WidgetVPNStatus(rawValue: persistedRaw) ?? .disconnected
            let shouldDisconnect = neStatus == .connected || neStatus == .connecting
                || persisted == .connected || persisted == .connecting
            if shouldDisconnect {
                manager.connection.stopVPNTunnel()
            }
        }

        await VPNIntentHelpers.waitForStableState(manager: manager)
        return .result()
    }
}
