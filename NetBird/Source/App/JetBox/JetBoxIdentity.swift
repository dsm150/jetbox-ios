//
//  JetBoxIdentity.swift
//  JetBox
//
//  Под какой «личностью» телефон встаёт в сеть по ссылке.
//
//  Личность устройства в NetBird — его ключ WireGuard. Ядро берёт ключ из
//  конфига, если тот уже есть, а management узнаёт существующий пир по ключу
//  и setup key из новой ссылки не применяет: ни группы, ни лимит ключа. Баг
//  13.11.2026: телефон с подключением коробки открыл ссылку облачного
//  абонента, согласился на замену — и остался прежним пиром в прежних
//  группах. Поэтому при замене подключения ключ создаётся заново.
//
//  Новый конфиг сначала регистрируется в отдельном файле и подменяет прежний
//  только после успеха: битая ссылка или нет сети не должны ломать то, что
//  работало. Старый пир на сервере не трогаем — его убирает Кабинет при
//  отзыве устройства.
//

import CryptoKit
import Foundation

enum JetBoxIdentity {

    enum Plan: Equatable {
        /// Тот же ключ: повторное открытие своей же ссылки или первый вход.
        case reuse
        /// Новый ключ: ссылка с другим setup key или на другой management.
        case fresh
    }

    static func plan(current: JetBoxBox?, payload: JetBoxLinkPayload, configExists: Bool) -> Plan {
        // Конфига нет — ядро и так создаст новый ключ.
        guard configExists else { return .reuse }
        // Конфиг остался не от JetBox (например, вход в расширенном режиме).
        guard let current else { return .fresh }
        guard managementHost(current.managementURL) == managementHost(payload.managementURL) else { return .fresh }
        if let known = current.setupKeyFingerprint {
            return known == fingerprint(of: payload.setupKey) ? .reuse : .fresh
        }
        // Запись сделана сборкой до 1.0 (9), отпечатка ключа в ней нет.
        return current.isSameConnection(as: payload) ? .reuse : .fresh
    }

    /// Отпечаток setup key: по нему отличаем «та же ссылка» от «новая ссылка»,
    /// не храня сам секрет.
    static func fingerprint(of setupKey: String) -> String {
        let digest = SHA256.hash(data: Data(setupKey.lowercased().utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Файл, в котором регистрируется новая личность, рядом с действующим конфигом.
    static func stagingPath(for configPath: String) -> String {
        configPath + ".jetbox-new"
    }

    /// Ставит зарегистрированный конфиг на место действующего.
    static func install(staging: String, into configPath: String) throws {
        let fm = FileManager.default
        let target = URL(fileURLWithPath: configPath)
        let source = URL(fileURLWithPath: staging)
        if fm.fileExists(atPath: configPath) {
            _ = try fm.replaceItemAt(target, withItemAt: source)
        } else {
            try fm.moveItem(at: source, to: target)
        }
    }

    private static func managementHost(_ url: String) -> String {
        URL(string: url)?.host?.lowercased() ?? url.lowercased()
    }
}
