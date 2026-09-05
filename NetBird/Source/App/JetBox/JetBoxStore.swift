//
//  JetBoxStore.swift
//  JetBox
//
//  Что приложение помнит между запусками: какая коробка сейчас прописана
//  на этом телефоне и включён ли расширенный режим.
//
//  Setup key здесь НЕ хранится. После успешной регистрации он больше не нужен:
//  ядро сохранило свой конфиг, а лишняя копия секрета на диске — лишний риск.
//

import Foundation

/// Коробка, к которой этот телефон уже привязан.
struct JetBoxBox: Codable, Equatable {
    var managementURL: String
    var exitNodeName: String?
    var boxName: String?
    var registeredAt: Date

    var displayName: String {
        if let boxName, !boxName.isEmpty { return boxName }
        if let exitNodeName, !exitNodeName.isEmpty { return exitNodeName }
        return URL(string: managementURL)?.host ?? managementURL
    }

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

    static var isAdvancedMode: Bool {
        UserDefaults.standard.bool(forKey: advancedModeKey)
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
            boxName: payload.boxName,
            registeredAt: Date()
        )
    }

    /// Выход, который клиент выбрал руками, важнее того, что был в ссылке.
    static func rememberExitNode(_ name: String?) {
        guard var box = currentBox else { return }
        box.exitNodeName = name
        currentBox = box
    }
}
