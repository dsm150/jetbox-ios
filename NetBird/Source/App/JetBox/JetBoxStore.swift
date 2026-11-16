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
//  Хранится только его отпечаток (SHA-256) — см. JetBoxIdentity.
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
    /// Отпечаток setup key, по которому телефон зарегистрирован. nil — запись
    /// сделана сборкой до 1.0 (9).
    var setupKeyFingerprint: String?
    /// Отпечаток токена приложения `t` — для удостоверения подключения.
    var appTokenFingerprint: String?

    var displayName: String {
        if let boxName, !boxName.isEmpty { return boxName }
        if let exitNodeName, !exitNodeName.isEmpty { return exitNodeName }
        return URL(string: managementURL)?.host ?? managementURL
    }

    /// Что показывать как текущий выход, пока туннель не поднят.
    var effectiveExitNode: String? { selectedExitNode ?? exitNodeName }

    var identity: String {
        JetBoxLinkIdentity.make(managementURL: managementURL, exitNode: exitNodeName,
                                appTokenFingerprint: appTokenFingerprint, boxName: boxName)
    }

    /// Имя дома из свежей ссылки того же JetBox. Объект могли переименовать в
    /// Кабинете — имя на телефоне обновляем сразу при открытии ссылки, не
    /// дожидаясь повторного подключения. nil — менять нечего (другой JetBox,
    /// в ссылке нет имени или оно то же).
    func renamed(by payload: JetBoxLinkPayload) -> JetBoxBox? {
        guard isSameConnection(as: payload),
              let name = payload.boxName, !name.isEmpty, name != boxName else { return nil }
        var box = self
        box.boxName = name
        return box
    }

    /// Ссылка ведёт к тому же подключению — тогда «переключить?» не спрашиваем.
    func isSameConnection(as payload: JetBoxLinkPayload) -> Bool {
        payload.boxIdentity == identity
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
            registeredAt: Date(),
            setupKeyFingerprint: JetBoxIdentity.fingerprint(of: payload.setupKey),
            appTokenFingerprint: payload.appToken.map(JetBoxIdentity.fingerprint(of:))
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
