//
//  JetBoxHomeOnlyGuard.swift
//  JetBox
//
//  «Только дом» (JetBoxEdition): при каждом подключении выход своей коробки
//  (`e` от Кабинета) включается, если он не выбран. Больше ничего: чужих
//  выходов у американского сервера нет, а сторож в сетевом расширении убран
//  в 1.0 (18) — «один в один как русская» (решение руководителя 22.11.2026).
//  Статус «Protected» — по факту маршрута 0.0.0.0/0 в туннеле (JetBoxTunnelState).
//

#if os(iOS)
import Foundation

enum JetBoxHomeOnlyGuard {

    struct Plan: Equatable {
        var select: String?
    }

    /// Что сделать с выходами: включить выход своей коробки (`allowed`), если
    /// он есть в маршрутах, но не выбран. Нет своего выхода — ничего.
    static func plan(selectedExit: String?, available: [String], allowed: String?, homeOnly: Bool) -> Plan {
        guard homeOnly, let allowed, selectedExit != allowed, available.contains(allowed) else { return Plan() }
        return Plan(select: allowed)
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
        if let name = plan.select, let node = routes.exitNodes.first(where: { $0.name == name }) {
            AppLogger.shared.log("JetBox: home only — selecting own box exit \(name)")
            routes.setExitNode(node)
        }
        // Проверка по ядру, а не по записи: какой выход там выбран на самом деле.
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        routes.getRoutes()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        AppLogger.shared.log("JetBox: exit in core after connect — \(routes.selectedExitNode?.name ?? "none") (own: \(allowed ?? "none")); default route in tunnel: \(JetBoxTunnelState.defaultRouteInTunnel() ? "yes" : "no")")
    }
}
#endif
