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
import Network
import CryptoKit

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
    /// `b`: mesh-адрес пира своей коробки (поле `box_ip` ответа verify, 1.0 (21)).
    /// Ядро говорит только с пиром с этим адресом (NB_ALLOWED_PEER_IP, патч 0004).
    var boxIP: String? = nil

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

    #if !JETBOX_US
    /// Общий выход облака: один `e` у всех абонентов (пространство `cl-` в
    /// NetBird, сейчас только `cl-exit`). Без `n` такой `e` абонента не
    /// различает, поэтому сравнение «без имени» для него запрещено.
    /// Только русская сборка: в сборке США общего выхода нет.
    static func isSharedExit(_ exitNode: String) -> Bool {
        exitNode.hasPrefix("cl-")
    }
    #endif

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
    /// Ссылка с любого хоста и с любым `m` (https) — без маски сервера и
    /// проверки хоста ссылки. Сборка США: решение владельца 23.11.2026
    /// («сними фильтр по доменам в ссылке»). Чужой сервер всё равно не даст
    /// чужих пиров и выхода: ядро держится пира своей коробки (патч 0004).
    var anyHost: Bool = false
    /// JetBox safety: ссылка принимается только с верной подписью `s`
    /// (JetBoxLinkSignature). Сборка США, 1.0 (25): любой сервер в `m`
    /// остаётся, подлинность ссылки — подписью (решение владельца 23.11.2026).
    var requiresSignature: Bool = false

    #if JETBOX_US
    static let editionAcceptsAnyHost = true
    static let editionRequiresSignature = true
    #else
    static let editionAcceptsAnyHost = false
    static let editionRequiresSignature = false
    #endif

    static var current: JetBoxLinkRules {
        JetBoxLinkRules(connectHost: JetBoxServers.connectLinkHost.lowercased(),
                        managementSuffix: JetBoxServers.managementSuffix.lowercased(),
                        defaultManagementURL: JetBoxServers.managementURL,
                        anyHost: editionAcceptsAnyHost,
                        requiresSignature: editionRequiresSignature)
    }

    /// Ссылка из ответа verify встроенного API (вход по email): она пришла по
    /// TLS с нашего сервера, подпись не нужна.
    var trustingSource: JetBoxLinkRules {
        var rules = self
        rules.requiresSignature = false
        return rules
    }
}

// MARK: - JetBox safety: подпись ссылки

/// JetBox safety — подпись ссылки подключения (спека
/// VPN_Box/docs/superpowers/specs/2026-11-23-link-signature-design.md).
///
/// `s` = base64url без «=» от Ed25519 по сообщению
/// `"JetBox safety v1\n"` + `"имя=значение\n"` для каждого параметра фрагмента,
/// кроме `s`, по возрастанию имени (байты UTF-8), значение — после
/// percent-decoding. Повтор любого имени — ссылка недействительна. Хост и путь
/// ссылки в подпись не входят. Шифрования нет — только проверка подлинности.
enum JetBoxLinkSignature {
    /// JetBox safety: открытые части ключа подписи ссылок (Ed25519, сырые
    /// 32 байта, base64). Подпись верна, если сходится с любой. Закрытые —
    /// только на наших серверах; резервная — на случай утечки основной.
    static let publicKeys: [String] = [
        "prLMY2riAVq0e1nuydlSO3FOFedlsNvxjKXsHUl8/Tg=",   // JetBox safety: основная
        "Lr8e8586oEZnBZqS678ipTemL050ha5OUIG6mqGyLu0=",   // JetBox safety: резервная
    ]

    #if DEBUG
    /// Только для тестов (тест-векторы на тестовом ключе). В релизной сборке
    /// этого свойства нет, тестовый ключ в приложение не попадает.
    static var testPublicKeys: [String] = []
    #endif

    static let messagePrefix = "JetBox safety v1\n"

    struct Signed: Equatable {
        let message: Data
        let signature: Data
    }

    /// Сообщение и подпись из фрагмента (без «#»). nil — подписи нет, она не
    /// 64 байта, есть повтор имени или пара без «=».
    static func signedMessage(fragment: String) -> Signed? {
        var seen = Set<String>()
        var fields: [(name: String, value: String)] = []
        var signature: Data?
        for pair in fragment.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty else { return nil }
            let name = String(parts[0])
            // Разбор ссылки имена не различает по регистру — повтор тоже.
            guard seen.insert(name.lowercased()).inserted else { return nil }
            let rawValue = String(parts[1])
            let value = rawValue.removingPercentEncoding ?? rawValue
            if name.lowercased() == "s" {
                signature = base64URLDecode(value)
                guard signature?.count == 64 else { return nil }
            } else {
                fields.append((name, value))
            }
        }
        guard let signature else { return nil }
        fields.sort { Array($0.name.utf8).lexicographicallyPrecedes(Array($1.name.utf8)) }
        var message = messagePrefix
        for field in fields { message += field.name + "=" + field.value + "\n" }
        return Signed(message: Data(message.utf8), signature: signature)
    }

    /// Подпись сходится с одной из открытых частей JetBox safety.
    static func isValid(fragment: String) -> Bool {
        guard let signed = signedMessage(fragment: fragment) else { return false }
        return keys.contains { $0.isValidSignature(signed.signature, for: signed.message) }
    }

    private static var keys: [Curve25519.Signing.PublicKey] {
        var all = publicKeys
        #if DEBUG
        all += testPublicKeys
        #endif
        return all.compactMap { Data(base64Encoded: $0) }
            .compactMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
    }

    /// base64url без «=»: только алфавит `A–Z a–z 0–9 - _`.
    static func base64URLDecode(_ text: String) -> Data? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
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
        /// JetBox safety (сборка США): нет подписи `s`, она неверна или в
        /// ссылке повтор параметра. Отказ до экрана подтверждения.
        case unsigned
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
        if rules.requiresSignature, !JetBoxLinkSignature.isValid(fragment: raw) { return .unsigned }
        guard isValidSetupKey(key) else { return .broken }

        if !rules.anyHost, let rawManagement = params["m"], !rawManagement.isEmpty,
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
            enablesDefaultExit: params["x"] != "0",
            boxIP: validIP(params["b"])
        ))
    }

    /// Адрес пира коробки: только IPv4/IPv6 без маски (маску, если сервер
    /// её прислал, отрезаем). Иначе nil — тогда ядро не пустит ни одного пира.
    static func validIP(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let bare = String(raw.trimmingCharacters(in: .whitespaces).split(separator: "/").first ?? "")
        // IPv4Address принимает и сокращённые формы («100.79.115»), а нам нужен
        // ровно тот адрес, что в карте сети: четыре октета.
        if bare.split(separator: ".", omittingEmptySubsequences: false).count == 4,
           let v4 = IPv4Address(bare) { return "\(v4)" }
        if bare.contains(":"), let v6 = IPv6Address(bare) { return "\(v6)" }
        return nil
    }

    /// Универсальная ссылка Кабинета либо своя схема. С `anyHost` — любой
    /// хост и путь: ссылкой подключения её делает ключ `k` во фрагменте.
    static func isJetBoxURL(_ url: URL, rules: JetBoxLinkRules = .current) -> Bool {
        let scheme = url.scheme?.lowercased()

        if scheme == JetBoxConfig.customScheme {
            return rules.anyHost || url.host?.lowercased() == "connect"
        }

        if scheme == "https" {
            if rules.anyHost { return true }
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
