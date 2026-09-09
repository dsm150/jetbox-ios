//
//  JetBoxLink.swift
//  JetBox
//
//  Разбор ссылки подключения из Кабинета.
//  Контракт формата — ~/Antigravity/JetBox_iOS/LINK-CONTRACT.md (редакция 1).
//
//  Ключ и параметры живут во ФРАГМЕНТЕ (после `#`): фрагмент не уходит на
//  сервер при открытии ссылки, поэтому setup key не попадает ни в access-логи
//  веб-сервера, ни в Referer, ни в историю редиректов. iOS доносит фрагмент до
//  приложения целиком — и в Universal Link, и в своей схеме.
//

import Foundation

// MARK: - Константы контракта

enum JetBoxConfig {
    /// Домен Кабинета, на котором лежит apple-app-site-association.
    static let universalLinkHost = "box.jet-net.net"
    /// Путь, который матчится в AASA (`/connect` и `/connect/*`).
    static let universalLinkPath = "/connect"
    /// Запасной вход: QR со старых материалов и кнопка на странице /connect.
    static let customScheme = "jetbox"
    /// Management по умолчанию — страховка для старых ссылок.
    /// Кабинет по контракту всегда кладёт `m=` явно.
    static let defaultManagementURL = "https://netbird.jet-net.net"
    /// Политика конфиденциальности: на неё ведёт «Подробнее» под объявлением
    /// о данных. App Review 5.4 требует объявить сбор данных на экране
    /// **до** того, как клиент нажмёт «Подключить».
    static let privacyPolicyURL = URL(string: "https://jet-net.net/privacy")!
}

// MARK: - Полезная нагрузка ссылки

struct JetBoxLinkPayload: Equatable, Codable {
    /// Setup key: 36 символов, валидный UUID. Целиком нигде не показывается.
    let setupKey: String
    /// Адрес management-сервера, всегда https.
    let managementURL: String
    /// Network ID маршрута-выхода коробки (`Client.SelectRoute(id)`), если прислан.
    let exitNodeName: String?
    /// Человекочитаемое имя коробки для экрана, если прислано.
    let boxName: String?

    /// Маска ключа для экрана и логов: видны только последние 4 символа.
    var maskedKey: String {
        guard setupKey.count > 4 else { return "••••" }
        return String(repeating: "•", count: 8) + "…" + setupKey.suffix(4)
    }

    /// Что показать клиенту как имя его коробки.
    var displayName: String {
        if let boxName, !boxName.isEmpty { return boxName }
        if let exitNodeName, !exitNodeName.isEmpty { return exitNodeName }
        return URL(string: managementURL)?.host ?? managementURL
    }

    /// Признак «та же коробка»: management + выход. По нему отличается
    /// повторный переход по своей ссылке от переезда на другую коробку.
    var boxIdentity: String {
        let host = URL(string: managementURL)?.host?.lowercased() ?? managementURL.lowercased()
        return host + "|" + (exitNodeName ?? "")
    }
}

// MARK: - Разбор

enum JetBoxLink {

    enum Outcome: Equatable {
        /// Ссылка наша и разобрана.
        case payload(JetBoxLinkPayload)
        /// Ссылка наша, но испорчена (кривой ключ, кривой management).
        /// Пользователю показываем «Ссылка повреждена», в сеть не идём.
        case broken
        /// Не наша ссылка — отдаём дальше по цепочке обработчиков.
        case notOurs
    }

    static func parse(_ url: URL) -> Outcome {
        guard isJetBoxURL(url) else { return .notOurs }

        // percentEncodedFragment, а не fragment: последний уже декодирован, и
        // повторное декодирование съело бы значения вида %2520 в `n=`.
        guard let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment,
              !raw.isEmpty else { return .notOurs }

        let params = parameters(fromFragment: raw)

        // Без ключа это не ссылка подключения: не пугаем клиента ошибкой,
        // просто не наш случай (для https откроется страница /connect).
        guard let key = params["k"], !key.isEmpty else { return .notOurs }
        guard isValidSetupKey(key) else { return .broken }

        let management = normalizedManagement(params["m"])
        guard let management else { return .broken }

        return .payload(JetBoxLinkPayload(
            setupKey: key,
            managementURL: management,
            exitNodeName: params["e"].flatMap { $0.isEmpty ? nil : $0 },
            boxName: params["n"].flatMap { $0.isEmpty ? nil : $0 }
        ))
    }

    /// Универсальная ссылка Кабинета либо своя схема.
    static func isJetBoxURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()

        if scheme == JetBoxConfig.customScheme {
            return url.host?.lowercased() == "connect"
        }

        if scheme == "https" {
            guard url.host?.lowercased() == JetBoxConfig.universalLinkHost else { return false }
            // AASA матчит `/connect` и `/connect/*` — принимаем то же самое.
            let path = url.path.lowercased()
            return path == JetBoxConfig.universalLinkPath
                || path.hasPrefix(JetBoxConfig.universalLinkPath + "/")
        }

        return false
    }

    // MARK: - Внутреннее

    /// Разбор `k=…&m=…&e=…`. Имена параметров регистронезависимы, значения
    /// percent-декодируются, `+` остаётся плюсом (в фрагменте это не пробел),
    /// неизвестные параметры игнорируются — это точка расширения контракта.
    private static func parameters(fromFragment fragment: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in fragment.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let name = String(parts[0]).lowercased()
            guard !name.isEmpty, result[name] == nil else { continue }
            let rawValue = String(parts[1])
            let value = (rawValue.removingPercentEncoding ?? rawValue)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result[name] = value
        }
        return result
    }

    /// Формат NetBird: ровно 36 символов и валидный UUID. Проверяем до любого
    /// сетевого вызова — кривая ссылка не должна стучаться в management.
    static func isValidSetupKey(_ key: String) -> Bool {
        key.count == 36 && UUID(uuidString: key) != nil
    }

    /// Только https, обязателен хост, хвостовой слэш срезаем.
    /// Пустое значение и отсутствие параметра — берём дефолт приложения.
    private static func normalizedManagement(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return JetBoxConfig.defaultManagementURL }
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty else { return nil }

        var normalized = "https://" + host.lowercased()
        if let port = components.port { normalized += ":\(port)" }
        let path = components.path
        if !path.isEmpty && path != "/" {
            normalized += path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        return normalized
    }
}
