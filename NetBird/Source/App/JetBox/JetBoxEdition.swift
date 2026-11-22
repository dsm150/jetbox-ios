//
//  JetBoxEdition.swift
//  JetBox
//
//  Редакция сборки. «Только дом» (английская сборка для App Store США,
//  решение владельца 21.11.2026): приложение подключается только к JetBox
//  пользователя и не выпускает трафик через чужие серверы — так написано в
//  Terms. Ноды JetNet, облако и выбор выхода в ней скрыты. Выход через СВОЮ
//  коробку (`e` от Кабинета, не `cl-…`) с 1.0 (14) снова есть и включён по
//  умолчанию (решение владельца 22.11.2026); выключается тумблером «All
//  internet through my JetBox». Русская сборка выключает флаг и получает всё
//  как было.
//
//  Переключение — настройка сборки `JETBOX_HOME_ONLY` у таргета NetBird
//  (YES по умолчанию), она попадает в Info.plist ключом `JetBoxHomeOnly`:
//    xcodebuild … JETBOX_HOME_ONLY=NO   — русская сборка с выходами.
//

import Foundation

enum JetBoxEdition {
    static let infoKey = "JetBoxHomeOnly"

    /// Флаг из Info.plist. Нет ключа или не подставилось значение — считаем
    /// «только дом»: безопаснее не включить выход, чем включить лишний.
    static let homeOnly: Bool = parse(Bundle.main.object(forInfoDictionaryKey: infoKey))

    static func parse(_ raw: Any?) -> Bool {
        if let flag = raw as? Bool { return flag }
        guard let text = (raw as? String)?.trimmingCharacters(in: .whitespaces).uppercased(),
              !text.isEmpty, !text.hasPrefix("$(") else { return true }
        return !["NO", "FALSE", "0"].contains(text)
    }

    /// Включать ли выход из ссылки после подключения: если ссылка не запрещает
    /// (`x=0`). «Только дом» — лишь выход своей коробки.
    static func appliesExit(payload: JetBoxLinkPayload, homeOnly: Bool) -> Bool {
        guard payload.enablesDefaultExit else { return false }
        return !homeOnly || ownExit(payload.exitNodeName) != nil
    }

    /// Выход своей коробки: имя `e`, пришедшее от Кабинета с этим профилем.
    /// Общие выходы облака (`cl-…`) своими не считаются.
    static func ownExit(_ name: String?) -> String? {
        guard let name, !name.isEmpty, !JetBoxLinkIdentity.isSharedExit(name) else { return nil }
        return name
    }

    /// Показывать ли тумблер «весь интернет через мой JetBox»: в «только дом»,
    /// когда у записи есть выход своей коробки.
    static func showsOwnExitToggle(homeOnly: Bool = homeOnly, box: JetBoxBox?) -> Bool {
        homeOnly && ownExit(box?.exitNodeName) != nil
    }

    /// Правообладатель в «О программе» (решение Алексея 21.11.2026):
    /// американская сборка — INSTASHOP Corporation, русская — JetNet, как было.
    static func copyrightHolder(homeOnly: Bool = homeOnly) -> String {
        homeOnly ? "INSTASHOP Corporation" : "JetNet"
    }

    /// Ключ строки о лицензии с правообладателем этой редакции.
    static func aboutLegalKey(homeOnly: Bool = homeOnly) -> String {
        homeOnly ? "jetbox.about.legal.us" : "jetbox.about.legal"
    }

    /// Сборка США без подключения показывает вход по email — и после «Sign out» тоже.
    static func showsEmailLogin(homeOnly: Bool = homeOnly, box: JetBoxBox?) -> Bool {
        homeOnly && box == nil
    }
}
