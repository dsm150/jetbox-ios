//
//  JetBoxHomeOnlyGuard.swift
//  JetBox
//
//  «Только дом» (JetBoxEdition): при подключении снимаем выход, если он остался
//  включённым с прежней сборки (русской, с выходами) на этом же телефоне.
//  Иначе трафик пошёл бы через чужой сервер — а Terms обещают только JetBox
//  пользователя (решение владельца 21.11.2026).
//

#if os(iOS)
import Foundation

enum JetBoxHomeOnlyGuard {

    /// Какой выход снять: в «только дом» — любой включённый, иначе — никакой.
    static func exitToDeselect(selectedExit: String?, homeOnly: Bool) -> String? {
        homeOnly ? selectedExit : nil
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
        guard let name = exitToDeselect(selectedExit: routes.selectedExitNode?.name, homeOnly: homeOnly) else { return }
        AppLogger.shared.log("JetBox: «только дом» — снимаю ранее включённый выход \(name)")
        routes.setExitNode(nil)
        JetBoxStore.rememberExitNode(nil)
    }
}
#endif
