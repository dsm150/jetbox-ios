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

    var displayName: String {
        if let boxName, !boxName.isEmpty { return boxName }
        if let exitNodeName, !exitNodeName.isEmpty { return exitNodeName }
        return URL(string: managementURL)?.host ?? managementURL
    }

    /// Что показывать как текущий выход, пока туннель не поднят.
    var effectiveExitNode: String? { selectedExitNode ?? exitNodeName }

    var identity: String {
        JetBoxLinkIdentity.make(managementURL: managementURL, exitNode: exitNodeName, boxName: boxName)
    }

    /// Имя в ссылке входит в удостоверение (§2.11), поэтому переименованная
    /// площадка спрашивает «переключить?» — цена принята руководителем 18.11.2026.
    /// Имя запоминаем, только когда в записи его не было: ссылка была без `n`.
    func named(by payload: JetBoxLinkPayload) -> JetBoxBox? {
        guard isSameConnection(as: payload), boxName?.isEmpty ?? true,
              let name = payload.boxName, !name.isEmpty else { return nil }
        var box = self
        box.boxName = name
        return box
    }

    /// Ссылка ведёт к тому же подключению — тогда «переключить?» не спрашиваем.
    /// Если имени нет у записи или у ссылки (старые ссылки без `n`), сравниваем
    /// без `n`: иначе первая же ссылка с именем дала бы ложное «Другой JetBox».
    func isSameConnection(as payload: JetBoxLinkPayload) -> Bool {
        if payload.boxIdentity == identity { return true }
        let nameMissing = (boxName?.isEmpty ?? true) || (payload.boxName?.isEmpty ?? true)
        guard nameMissing, let exit = exitNodeName, !exit.isEmpty,
              !JetBoxLinkIdentity.isSharedExit(exit) else { return false }
        return JetBoxLinkIdentity.withoutName(managementURL: payload.managementURL, exitNode: payload.exitNodeName)
            == JetBoxLinkIdentity.withoutName(managementURL: managementURL, exitNode: exitNodeName)
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
            defer { shareOwnExit(newValue) }
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: boxKey)
                return
            }
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: boxKey)
            }
        }
    }

    /// Выход своей коробки — для сетевого расширения: в «только дом» оно
    /// пропускает только его, и он включён всегда (1.0 (16), тумблера нет).
    static func ownExitToAllow(for box: JetBoxBox?, homeOnly: Bool = JetBoxEdition.homeOnly) -> String? {
        homeOnly ? JetBoxEdition.ownExit(box?.exitNodeName) : nil
    }

    static func shareOwnExit(_ box: JetBoxBox?, file: URL? = JetBoxSharedExit.defaultURL()) {
        JetBoxSharedExit.write(ownExitToAllow(for: box), at: file)
        // Ключ 1.0 (14) больше не читается — убираем, чтобы не путал.
        UserDefaults(suiteName: GlobalConstants.userPreferencesSuiteName)?
            .removeObject(forKey: GlobalConstants.keyJetBoxOwnExit)
    }

    /// Весь интернет идёт через свою коробку (сборка США, есть `e` своей коробки).
    static var allInternetHome: Bool { ownExitToAllow(for: currentBox) != nil }

    /// Записи 1.0 (12–15): выход своей коробки мог быть не выбран (x=0 или
    /// тумблер). С 1.0 (16) он выбран всегда.
    static func selectOwnExitIfNeeded(homeOnly: Bool = JetBoxEdition.homeOnly) {
        guard let box = currentBox, let own = ownExitToAllow(for: box, homeOnly: homeOnly),
              box.selectedExitNode != own else { return }
        rememberExitNode(own)
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
            // `x=0`: выход из ссылки только разрешён, не включён (контракт 1.2, §2.10).
            // «Только дом»: выход своей коробки — всегда, `x` не смотрим (JetBoxEdition).
            selectedExitNode: JetBoxEdition.appliesExit(payload: payload, homeOnly: JetBoxEdition.homeOnly)
                ? payload.exitNodeName : nil,
            boxName: payload.boxName,
            registeredAt: Date(),
            setupKeyFingerprint: JetBoxIdentity.fingerprint(of: payload.setupKey)
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
