import AppIntents
import NetworkExtension
import WidgetKit

@available(iOS 16.0, *)
struct ConnectVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "Подключить JetBox"
    static var description: IntentDescription = "Подключение к вашей сети JetBox."
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let manager = try await VPNIntentHelpers.loadManager() else {
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "JetBox ещё не настроен.")
        }

        guard !VPNIntentHelpers.isLoginRequired else {
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "Нужно открыть приложение JetBox.")
        }

        let status = manager.connection.status
        guard status == .disconnected || status == .invalid else {
            return .result(dialog: "JetBox уже \(WidgetVPNStatus(neStatus: status).displayText.lowercased()).")
        }

        VPNIntentHelpers.defaults?.set(WidgetVPNStatus.connecting.rawValue, forKey: WidgetConstants.keyVPNStatus)
        WidgetCenter.shared.reloadAllTimelines()

        do {
            try await VPNIntentHelpers.startTunnel(manager: manager)
        } catch {
            VPNIntentHelpers.defaults?.set(WidgetVPNStatus.disconnected.rawValue, forKey: WidgetConstants.keyVPNStatus)
            WidgetCenter.shared.reloadAllTimelines()
            throw error
        }

        let final = await VPNIntentHelpers.waitForStableState(manager: manager)
        if final == .connected {
            return .result(dialog: "JetBox подключён.")
        } else if VPNIntentHelpers.isLoginRequired {
            return .result(dialog: "Нужно открыть приложение JetBox.")
        } else {
            return .result(dialog: "Не удалось подключить JetBox.")
        }
    }
}
