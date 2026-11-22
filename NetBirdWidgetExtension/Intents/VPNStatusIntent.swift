import AppIntents
import NetworkExtension

@available(iOS 16.0, *)
struct VPNStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "JetBox status"
    static var description: IntentDescription = "Check whether JetBox is connected."
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let manager = try await VPNIntentHelpers.loadManager() else {
            return .result(dialog: "JetBox is not set up yet.")
        }

        if VPNIntentHelpers.isLoginRequired {
            return .result(dialog: "Open the JetBox app to continue.")
        }

        let status = WidgetVPNStatus(neStatus: manager.connection.status)
        let ip = VPNIntentHelpers.defaults?.string(forKey: WidgetConstants.keyIP) ?? ""
        let detail = status == .connected && !ip.isEmpty ? String(localized: " Your IP address is \(ip).") : ""

        return .result(dialog: "JetBox: \(status.displayText.lowercased()).\(detail)")
    }
}
