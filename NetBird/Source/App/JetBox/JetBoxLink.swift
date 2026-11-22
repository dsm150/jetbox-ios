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
    /// Домен Кабинета, на котором лежит apple-app-site-association
    /// (Config/JetBoxEdition.xcconfig → Info.plist).
    static var universalLinkHost: String { JetBoxServers.connectLinkHost }
    /// Путь, который матчится в AASA (`/connect` и `/connect/*`).
    static let universalLinkPath = "/connect"
    /// Запасной вход: QR со старых материалов и кнопка на странице /connect.
    static let customScheme = "jetbox"
    /// Management по умолчанию — страховка для старых ссылок.
    /// Кабинет по контракту всегда кладёт `m=` явно.
    static var defaultManagementURL: String { JetBoxServers.managementURL }
    /// Политика конфиденциальности: на неё ведёт «Подробнее» под объявлением
    /// о данных. App Review 5.4 требует объявить сбор данных на экране
    /// **до** того, как клиент нажмёт «Подключить».
    /// Юридические страницы — на сайте JetBox для США (Алексей, 21.11.2026).
    static let privacyPolicyURL = URL(string: "https://jetbox.ai-boss.us/legal/#privacy")!
    static let termsURL = URL(string: "https://jetbox.ai-boss.us/legal/#terms")!
    static let eulaURL = URL(string: "https://jetbox.ai-boss.us/legal/#eula")!
    static let siteURL = URL(string: "https://jetbox.ai-boss.us")!
    /// Исходники форка и текст лицензии — GPL-3.0 требует их доступности.
    static let sourceCodeURL = URL(string: "https://github.com/dsm150/jetbox-ios")!
    static let licenseURL = URL(string: "https://github.com/dsm150/jetbox-ios/blob/main/LICENSE")!
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
    /// Токен приложения устройства (`t`, контракт 1.2): Bearer к API устройства
    /// Кабинета. iOS API пока не вызывает и токен не хранит; в удостоверение он
    /// не входит — меняется при «Новой ссылке» (контракт 1.3, §2.11).
    var appToken: String? = nil
    /// `x=0`: выход в интернет по умолчанию не включать (облачный тариф).
    var enablesDefaultExit: Bool = true

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

    /// Удостоверение подключения (контракт 1.3, §2.11). Решает только, спросить
    /// ли «переключить?»; нужен ли новый ключ, решает отпечаток setup key.
    var boxIdentity: String {
        JetBoxLinkIdentity.make(managementURL: managementURL, exitNode: exitNodeName, boxName: boxName)
    }
}

/// Одно правило удостоверения для ссылки и для сохранённой коробки
/// (контракт 1.3, §2.11): `хост(m)|e|n`, без `e` — `хост(m)|n:<n>`.
/// `n` входит потому, что у всех облачных абонентов один `e=cl-exit`, а `n`
/// у них разный («JetBox · <абонент>») и при «Новой ссылке» не меняется.
/// `n` — как есть после percent-decoding и обрезки пробелов, с учётом регистра.
enum JetBoxLinkIdentity {
    static func make(managementURL: String, exitNode: String?, boxName: String?) -> String {
        let host = URL(string: managementURL)?.host?.lowercased() ?? managementURL.lowercased()
        let name = boxName ?? ""
        if let exitNode, !exitNode.isEmpty { return host + "|" + exitNode + "|" + name }
        if !name.isEmpty { return host + "|n:" + name }
        return host + "|"
    }

    /// Общий выход облака: один `e` у всех абонентов (пространство `cl-` в
    /// NetBird, сейчас только `cl-exit`). Без `n` такой `e` абонента не
    /// различает, поэтому сравнение «без имени» для него запрещено.
    static func isSharedExit(_ exitNode: String) -> Bool {
        exitNode.hasPrefix("cl-")
    }

    /// Удостоверение без `n` — для записей, где имени нет (ссылка была без `n`).
    static func withoutName(managementURL: String, exitNode: String?) -> String {
        make(managementURL: managementURL, exitNode: exitNode, boxName: nil)
    }
}

// MARK: - Разбор

/// Хосты, по которым разбирается ссылка подключения. В приложении — всегда
/// `.current` (адреса редакции из Info.plist); тесты подставляют свои.
struct JetBoxLinkRules: Equatable {
    var connectHost: String
    var managementSuffix: String
    var defaultManagementURL: String

    static var current: JetBoxLinkRules {
        JetBoxLinkRules(connectHost: JetBoxServers.connectLinkHost.lowercased(),
                        managementSuffix: JetBoxServers.managementSuffix.lowercased(),
                        defaultManagementURL: JetBoxServers.managementURL)
    }
}

enum JetBoxLink {

    enum Outcome: Equatable {
        /// Ссылка наша и разобрана.
        case payload(JetBoxLinkPayload)
        /// Ссылка наша, но испорчена (кривой ключ, кривой management).
        /// Пользователю показываем «Ссылка повреждена», в сеть не идём.
        case broken
        /// `m` вне маски сервера редакции (контракт 1.3, §2.3): ссылка ведёт не на
        /// сервер JetBox. Отказ до любого вопроса, в сеть не идём.
        case foreignServer
        /// Не наша ссылка — отдаём дальше по цепочке обработчиков.
        case notOurs
    }

    static func parse(_ url: URL, rules: JetBoxLinkRules = .current) -> Outcome {
        guard isJetBoxURL(url, rules: rules) else { return .notOurs }

        // percentEncodedFragment, а не fragment: последний уже декодирован, и
        // повторное декодирование съело бы значения вида %2520 в `n=`.
        guard let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment,
              !raw.isEmpty else { return .notOurs }

        let params = parameters(fromFragment: raw)

        // Без ключа это не ссылка подключения: не пугаем клиента ошибкой,
        // просто не наш случай (для https откроется страница /connect).
        guard let key = params["k"], !key.isEmpty else { return .notOurs }
        guard isValidSetupKey(key) else { return .broken }

        if let rawManagement = params["m"], !rawManagement.isEmpty,
           !allowedManagement(rawManagement, suffix: rules.managementSuffix) {
            return .foreignServer
        }
        let management = normalizedManagement(params["m"], fallback: rules.defaultManagementURL)
        guard let management else { return .broken }

        return .payload(JetBoxLinkPayload(
            setupKey: key,
            managementURL: management,
            exitNodeName: params["e"].flatMap { $0.isEmpty ? nil : $0 },
            boxName: params["n"].flatMap { $0.isEmpty ? nil : $0 },
            appToken: params["t"].flatMap { $0.isEmpty ? nil : $0 },
            enablesDefaultExit: params["x"] != "0"
        ))
    }

    /// Универсальная ссылка Кабинета либо своя схема.
    static func isJetBoxURL(_ url: URL, rules: JetBoxLinkRules = .current) -> Bool {
        let scheme = url.scheme?.lowercased()

        if scheme == JetBoxConfig.customScheme {
            return url.host?.lowercased() == "connect"
        }

        if scheme == "https" {
            guard !rules.connectHost.isEmpty, url.host?.lowercased() == rules.connectHost else { return false }
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

    /// Домен, на поддоменах которого разрешён management (решение владельца
    /// 18.11.2026; домен — по редакции, Config/JetBoxEdition.xcconfig). Правило
    /// одно на все платформы: эталон — `JetBox_Desktop/core/jetboxlink/mask.go`,
    /// общие векторы — `mgmt-mask.json`.
    static var managementSuffix: String { JetBoxServers.managementSuffix }

    /// `m` (уже без percent-encoding) разрешён маской: https, без логина, пути
    /// (кроме «/»), query и фрагмента; хост — имя ASCII (не IP), оканчивается на
    /// маску `suffix` (сам домен без поддомена — нет); порт — любой 1–65535.
    /// Разбираем сами, а не URLComponents: тот декодирует `%2E` в хосте.
    static func allowedManagement(_ raw: String, suffix: String = managementSuffix) -> Bool {
        let scheme = "https://"
        guard raw.count > scheme.count, raw.lowercased().hasPrefix(scheme) else { return false }
        let rest = raw.dropFirst(scheme.count)
        // Логин, query, фрагмент, обратный слэш, пробелы — сразу мимо.
        guard rest.allSatisfy({ $0.isASCII && !$0.isWhitespace && !"@?#\\".contains($0) }) else { return false }

        let authority: Substring
        if let slash = rest.firstIndex(of: "/") {
            guard rest[slash...] == "/" else { return false }
            authority = rest[..<slash]
        } else {
            authority = rest
        }
        guard !authority.hasPrefix("[") else { return false }   // IPv6

        var host = authority
        if let colon = authority.lastIndex(of: ":") {
            // Двоеточие без порта — отказ (вектор 36, найден Android 18.11.2026).
            let port = authority[authority.index(after: colon)...]
            guard !port.isEmpty, port.allSatisfy(\.isASCIIDigit),
                  let number = Int(port), (1...65535).contains(number) else { return false }
            host = authority[..<colon]
        }

        var name = host.lowercased()
        if name.hasSuffix(".") { name.removeLast() }
        guard !name.isEmpty,
              name.allSatisfy({ ("a"..."z").contains($0) || $0.isASCIIDigit || $0 == "-" || $0 == "." }),
              !name.split(separator: ".", omittingEmptySubsequences: false).contains(where: \.isEmpty),
              !isIPv4(name) else { return false }
        guard suffix.hasPrefix("."), suffix.count > 1 else { return false }
        return name.hasSuffix(suffix) && name.count > suffix.count
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }
    }

    /// Только https, обязателен хост, хвостовой слэш срезаем.
    /// Пустое значение и отсутствие параметра — берём дефолт приложения.
    private static func normalizedManagement(_ value: String?, fallback: String) -> String? {
        guard let value, !value.isEmpty else { return fallback.isEmpty ? nil : fallback }
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty else { return nil }

        // Одна завершающая точка FQDN срезается до маски и удостоверения:
        // `mgmt.example.` — тот же сервер (находка Android, 18.11.2026).
        var name = host.lowercased()
        if name.hasSuffix(".") { name.removeLast() }
        var normalized = "https://" + name
        if let port = components.port { normalized += ":\(port)" }
        let path = components.path
        if !path.isEmpty && path != "/" {
            normalized += path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        return normalized
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
