//
//  JetBoxEdition.swift
//  JetBox
//
//  Редакция сборки. «Только дом» (английская сборка для App Store США,
//  решение владельца 21.11.2026): приложение подключается только к JetBox
//  пользователя и не выпускает трафик через чужие серверы — так написано в
//  Terms. Ноды JetNet, облако и выбор выхода в ней скрыты. Выход через СВОЮ
//  коробку (`e` от Кабинета, не `cl-…`) с 1.0 (14) снова есть и с 1.0 (16)
//  включён всегда — тумблера нет, `x` игнорируется (решение владельца
//  22.11.2026: защиту нельзя выключить и забыть в кафе). Русская сборка
//  выключает флаг и получает всё как было.
//
//  Переключение — настройка сборки `JETBOX_HOME_ONLY` у таргета NetBird
//  (YES по умолчанию), она попадает в Info.plist ключом `JetBoxHomeOnly`:
//    xcodebuild … JETBOX_HOME_ONLY=NO   — русская сборка с выходами.
//

import Foundation

enum JetBoxEdition {
    #if JETBOX_US
    /// Сборка США — всегда «только дом»: ветки русской сборки (выход по `x`,
    /// общий выход облака `cl-…`) в неё не компилируются (сборка 1.0 (20),
    /// требование SiteDev и Алексея).
    static let homeOnly = true
    #else
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
    #endif

    /// Включать ли выход из ссылки после подключения. «Только дом» — всегда,
    /// если это выход своей коробки, `x` не смотрим; иначе — если ссылка не
    /// запрещает (`x=0`).
    static func appliesExit(payload: JetBoxLinkPayload, homeOnly: Bool) -> Bool {
        #if JETBOX_US
        return ownExit(payload.exitNodeName) != nil
        #else
        if homeOnly { return ownExit(payload.exitNodeName) != nil }
        return payload.enablesDefaultExit
        #endif
    }

    /// Выход своей коробки: имя `e`, пришедшее от Кабинета с этим профилем.
    /// В сборке США других выходов нет: ядро пропускает 0.0.0.0/0 только с
    /// этим именем (NB_ALLOWED_EXIT, патч 0004). В русской общие выходы облака
    /// (`cl-…`) своими не считаются.
    static func ownExit(_ name: String?) -> String? {
        #if JETBOX_US
        guard let name, !name.isEmpty else { return nil }
        #else
        guard let name, !name.isEmpty, !JetBoxLinkIdentity.isSharedExit(name) else { return nil }
        #endif
        return name
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
