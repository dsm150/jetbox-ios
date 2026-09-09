import AppIntents

@available(iOS 16.0, *)
struct NetBirdShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConnectVPNIntent(),
            phrases: [
                "Подключить \(.applicationName)",
                "Включить \(.applicationName)",
                "Соединение \(.applicationName)"
            ],
            shortTitle: "Подключить",
            systemImageName: "lock.shield"
        )

        AppShortcut(
            intent: DisconnectVPNIntent(),
            phrases: [
                "Отключить \(.applicationName)",
                "Выключить \(.applicationName)",
                "Разорвать соединение \(.applicationName)"
            ],
            shortTitle: "Отключить",
            systemImageName: "lock.slash"
        )

        AppShortcut(
            intent: VPNStatusIntent(),
            phrases: [
                "Состояние \(.applicationName)",
                "\(.applicationName) подключён",
                "Проверить \(.applicationName)"
            ],
            shortTitle: "Состояние",
            systemImageName: "network"
        )
    }
}
