//
//  JetBoxHomeOnlyGuard.swift
//  JetBox
//
//  «Только дом» (JetBoxEdition): при подключении приводим выход в порядок.
//  Чужой выход (нода JetNet, облако, остаток с русской сборки на этом же
//  телефоне) снимаем — Terms обещают только JetBox пользователя (решение
//  владельца 21.11.2026). Выход своей коробки включаем, если его нет: он
//  включён всегда (1.0 (16), решение владельца 22.11.2026). То же самое
//  делает и сетевое расширение — оно работает и без приложения (виджет, Пункт управления).
//

#if os(iOS)
import Foundation

enum JetBoxHomeOnlyGuard {

    struct Plan: Equatable {
        var deselect: String?
        var select: String?
    }

    /// Что сделать с выходами. `allowed` — выход своей коробки, nil — его нет
    /// (тогда снимается любой выход).
    static func plan(selectedExit: String?, available: [String], allowed: String?, homeOnly: Bool) -> Plan {
        guard homeOnly else { return Plan() }
        var plan = Plan()
        if let selectedExit, selectedExit != allowed { plan.deselect = selectedExit }
        if let allowed, selectedExit != allowed, available.contains(allowed) { plan.select = allowed }
        return plan
    }

    /// Маршруты после подключения приходят не сразу — ждём их до ~5 с.
    @MainActor
    static func enforce(routes: RoutesViewModel, homeOnly: Bool = JetBoxEdition.homeOnly) async {
        guard homeOnly else { return }
        for _ in 0..<6 {
            routes.getRoutes()
            try? await Task.sleep(nanoseconds: 800_000_000)
            if !routes.exitNodes.isEmpty { break }
        }
        let allowed = JetBoxStore.ownExitToAllow(for: JetBoxStore.currentBox)
        let plan = plan(selectedExit: routes.selectedExitNode?.name,
                        available: routes.exitNodes.map(\.name), allowed: allowed, homeOnly: homeOnly)
        // Выбор выхода в RoutesViewModel сам снимает остальные выходы.
        if let name = plan.select, let node = routes.exitNodes.first(where: { $0.name == name }) {
            AppLogger.shared.log("JetBox: «только дом» — включаю выход своей коробки \(name)")
            routes.setExitNode(node)
        } else if let name = plan.deselect {
            AppLogger.shared.log("JetBox: «только дом» — снимаю выход \(name)")
            routes.setExitNode(nil)
        }
        // Проверка по ядру, а не по записи: какой выход там выбран на самом деле.
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        routes.getRoutes()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        AppLogger.shared.log("JetBox: выход в ядре после подключения — \(routes.selectedExitNode?.name ?? "нет") (свой: \(allowed ?? "нет")); маршрут по умолчанию в туннеле: \(JetBoxTunnelState.defaultRouteInTunnel() ? "да" : "нет")")
    }
}
#endif
