//
//  JetBoxEdition.swift
//  JetBox
//
//  Редакция сборки. «Только дом» (английская сборка для App Store США,
//  решение владельца 21.11.2026): приложение подключается только к JetBox
//  пользователя и не выпускает трафик через другие серверы — так написано в
//  Terms. Выходы и облако в ней скрыты: нет выбора выхода, `e`/`x` из ссылки
//  выход не включают, экраны выхода не показываются. Код выходов не удалён:
//  русская сборка выключает флаг и получает всё как было.
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

    /// Включать ли выход из ссылки после подключения. «Только дом» — никогда;
    /// иначе — если ссылка не запрещает (`x=0`).
    static func appliesExit(payload: JetBoxLinkPayload, homeOnly: Bool) -> Bool {
        !homeOnly && payload.enablesDefaultExit
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
