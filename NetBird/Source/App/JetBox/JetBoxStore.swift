//
//  JetBoxStore.swift
//  JetBox
//
//  Что приложение помнит между запусками: какой JetBox сейчас прописан
//  на этом телефоне. Состояние расширенных настроек живёт отдельно, в App
//  Group — см. JetBoxAdvancedAccess.
//
//  Setup key здесь НЕ хранится. После успешной регистрации он больше не нужен:
//  ядро сохранило свой конфиг, а лишняя копия секрета на диске — лишний риск.
//

import Foundation

/// Коробка, к которой этот телефон уже привязан.
struct JetBoxBox: Codable, Equatable {
    var managementURL: String
    /// Выход, который был в ссылке. Часть удостоверения коробки — по нему
    /// отличается «моя ссылка» от «ссылка на другую коробку».
    var exitNodeName: String?
    /// Выход, который сейчас выбран. Пользователь мог сменить его руками —
    /// на удостоверение коробки это влиять не должно, иначе своя же ссылка
    /// начнёт спрашивать «переключить на другую коробку?».
    var selectedExitNode: String?
    var boxName: String?
    var registeredAt: Date

    var displayName: String {
        if let boxName, !boxName.isEmpty { return boxName }
        if let exitNodeName, !exitNodeName.isEmpty { return exitNodeName }
        return URL(string: managementURL)?.host ?? managementURL
    }

    /// Что показывать как текущий выход, пока туннель не поднят.
    var effectiveExitNode: String? { selectedExitNode ?? exitNodeName }

    var identity: String {
        let host = URL(string: managementURL)?.host?.lowercased() ?? managementURL.lowercased()
        return host + "|" + (exitNodeName ?? "")
    }
}

enum JetBoxStore {

    private static let boxKey = "jetbox.currentBox"

    /// Ключ расширенного режима. Значение по умолчанию (false) = простой режим:
    /// апстримовые экраны NetBird спрятаны, но не удалены — иначе каждый ребейз
    /// превращался бы в разбор конфликтов.
    ///
    /// Само значение с 09.09.2026 живёт в App Group и меняется только через
    /// `JetBoxAdvancedAccess` (семь нажатий по строке версии), а не тумблером.
    static let advancedModeKey = "jetbox.advancedMode"

    static var currentBox: JetBoxBox? {
        get {
            guard let data = UserDefaults.standard.data(forKey: boxKey) else { return nil }
            return try? JSONDecoder().decode(JetBoxBox.self, from: data)
        }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: boxKey)
                return
            }
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: boxKey)
            }
        }
    }

    /// Экран первого запуска апстрима («подключитесь к облаку NetBird») клиенту
    /// JetBox показывать незачем — коробка приходит ссылкой.
    static func skipUpstreamOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    static func remember(_ payload: JetBoxLinkPayload) {
        currentBox = JetBoxBox(
            managementURL: payload.managementURL,
            exitNodeName: payload.exitNodeName,
            selectedExitNode: payload.exitNodeName,
            boxName: payload.boxName,
            registeredAt: Date()
        )
    }

    /// Выход, который клиент выбрал руками, важнее того, что был в ссылке —
    /// но удостоверение коробки не трогает.
    static func rememberExitNode(_ name: String?) {
        guard var box = currentBox else { return }
        box.selectedExitNode = name
        currentBox = box
    }
}
