import AppIntents
import NetworkExtension

@available(iOS 16.0, *)
struct VPNStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Состояние JetBox"
    static var description: IntentDescription = "Проверка, подключён ли JetBox."
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let manager = try await VPNIntentHelpers.loadManager() else {
            return .result(dialog: "JetBox ещё не настроен.")
        }

        if VPNIntentHelpers.isLoginRequired {
            return .result(dialog: "Нужно открыть приложение JetBox.")
        }

        let status = WidgetVPNStatus(neStatus: manager.connection.status)
        let ip = VPNIntentHelpers.defaults?.string(forKey: WidgetConstants.keyIP) ?? ""
        let detail = status == .connected && !ip.isEmpty ? String(localized: " Ваш адрес \(ip).") : ""

        return .result(dialog: "JetBox: \(status.displayText.lowercased()).\(detail)")
    }
}
