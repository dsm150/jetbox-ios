import AppIntents
import NetworkExtension
import WidgetKit

@available(iOS 16.0, *)
struct DisconnectVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "Отключить JetBox"
    static var description: IntentDescription = "Отключение от вашей сети JetBox."
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let manager = try await VPNIntentHelpers.loadManager() else {
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "JetBox ещё не настроен.")
        }

        let status = manager.connection.status
        guard status == .connected || status == .connecting else {
            return .result(dialog: "JetBox уже отключён.")
        }

        VPNIntentHelpers.defaults?.set(WidgetVPNStatus.disconnecting.rawValue, forKey: WidgetConstants.keyVPNStatus)
        WidgetCenter.shared.reloadAllTimelines()

        manager.connection.stopVPNTunnel()

        let final = await VPNIntentHelpers.waitForStableState(manager: manager)
        if final == .disconnected {
            return .result(dialog: "JetBox отключён.")
        } else {
            return .result(dialog: "Не удалось отключить JetBox.")
        }
    }
}
