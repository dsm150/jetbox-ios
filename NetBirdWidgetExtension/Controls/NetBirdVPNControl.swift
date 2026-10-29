import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct NetBirdVPNControl: ControlWidget {

    static let kind = "net.jetnet.jetbox.vpn.control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: Self.kind,
            provider: VPNControlProvider()
        ) { state in
            ControlWidgetToggle(
                isOn: state.isActive,
                action: SetVPNStateIntent()
            ) { 
                Label("Подключить JetBox", image: "jetbox-mark")
            }
            .tint(.jetboxBlue)
        }
        .displayName("JetBox")
        .description("Подключение и отключение JetBox из Пункта управления.")
    }
}
