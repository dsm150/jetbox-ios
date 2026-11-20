import AppIntents

@available(iOS 16.0, *)
struct NetBirdShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConnectVPNIntent(),
            phrases: [
                "Connect \(.applicationName)",
                "Turn on \(.applicationName)",
                "Connect to home with \(.applicationName)"
            ],
            shortTitle: "Connect",
            systemImageName: "lock.shield"
        )

        AppShortcut(
            intent: DisconnectVPNIntent(),
            phrases: [
                "Disconnect \(.applicationName)",
                "Turn off \(.applicationName)",
                "Disconnect from home with \(.applicationName)"
            ],
            shortTitle: "Disconnect",
            systemImageName: "lock.slash"
        )

        AppShortcut(
            intent: VPNStatusIntent(),
            phrases: [
                "\(.applicationName) status",
                "Is \(.applicationName) connected",
                "Check \(.applicationName)"
            ],
            shortTitle: "Status",
            systemImageName: "network"
        )
    }
}
