import AppIntents
import NetworkExtension
import WidgetKit

@available(iOS 16.0, *)
struct ConnectVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "Connect JetBox"
    static var description: IntentDescription = "Connect to your home network."
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let manager = try await VPNIntentHelpers.loadManager() else {
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "JetBox is not set up yet.")
        }

        guard !VPNIntentHelpers.isLoginRequired else {
            WidgetCenter.shared.reloadAllTimelines()
            return .result(dialog: "Open the JetBox app to continue.")
        }

        let status = manager.connection.status
        guard status == .disconnected || status == .invalid else {
            return .result(dialog: "Nothing to change: \(WidgetVPNStatus(neStatus: status).displayText.lowercased()).")
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
            return .result(dialog: "JetBox connected.")
        } else if VPNIntentHelpers.isLoginRequired {
            return .result(dialog: "Open the JetBox app to continue.")
        } else {
            return .result(dialog: "JetBox couldn’t connect.")
        }
    }
}
