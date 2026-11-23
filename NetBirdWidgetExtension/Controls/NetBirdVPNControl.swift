import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct NetBirdVPNControl: ControlWidget {

    #if JETBOX_US
    static let kind = "us.aiboss.jetbox.vpn.control"
    #else
    static let kind = "net.jetnet.jetbox.vpn.control"
    #endif

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: Self.kind,
            provider: VPNControlProvider()
        ) { state in
            ControlWidgetToggle(
                isOn: state.isActive,
                action: SetVPNStateIntent()
            ) { 
                Label("Connect JetBox", image: "jetbox-mark")
            }
            .tint(.jetboxBlue)
        }
        .displayName("JetBox")
        .description("Connect or disconnect JetBox from Control Center.")
    }
}
