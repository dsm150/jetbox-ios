//
//  JetBoxSupport.swift
//  JetBox
//
//  «Help» (1.0 (34), спека
//  VPN_Box/docs/superpowers/specs/2026-11-28-app-help-and-dns-check-design.md §2, §3а).
//
//  Есть токен приложения (вход по почте) — `POST support` к своему Кабинету:
//  сообщение ложится в тред поддержки клиента. Токена нет или Кабинет не
//  принял — письмо на адрес поддержки рынка: последний, что прислал Кабинет
//  (`support_email` в любом ответе, `support` в 409 last_owner), иначе
//  встроенный. Диагностика — только то, что нужно для разбора, без секретов.
//

import Foundation

// MARK: - Адрес поддержки

enum JetBoxSupportContact {
    static let key = "jetbox.supportEmail"

    /// Запоминает адрес от Кабинета; не адрес (телефон, пусто) — пропускаем.
    static func remember(_ value: String?, defaults: UserDefaults = JetBoxAdvancedAccess.defaults) {
        guard let value = value?.trimmingCharacters(in: .whitespaces), isEmail(value) else { return }
        defaults.set(value, forKey: key)
    }

    static func current(defaults: UserDefaults = JetBoxAdvancedAccess.defaults) -> String {
        defaults.string(forKey: key).flatMap { isEmail($0) ? $0 : nil } ?? JetBoxOnboarding.defaultSupportEmail
    }

    static func isEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !value.contains(" ")
    }
}

// MARK: - Кабинет

extension JetBoxLoginAPI {
    enum SupportOutcome: Equatable {
        /// 200: `promise` — обещание срока ответа от Кабинета.
        case sent(promise: String?)
        /// 429.
        case rateLimited
        /// 401, 413, прочие ответы, сеть — уходим в письмо.
        case needsMail
    }

    static let supportMessageLimit = 4000
    static let supportDiagnosticsLimit = 16000

    /// POST support с `Authorization: Bearer <app_token>` (§3а).
    func sendSupport(token: String, message: String, diagnostics: String,
                     version: String, lang: String) async -> SupportOutcome {
        var request = URLRequest(url: base.appendingPathComponent("support"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let body: [String: String] = [
            "message": String(message.prefix(Self.supportMessageLimit)),
            "diagnostics": String(diagnostics.prefix(Self.supportDiagnosticsLimit)),
            "platform": "ios", "version": version, "lang": lang,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await transport(request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            JetBoxSupportContact.remember(json?["support_email"] as? String)
            log("JetBox: help — server answered \(code)")
            switch code {
            case 200:
                let promise = (json?["promise"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return .sent(promise: promise?.isEmpty == false ? promise : nil)
            case 429: return .rateLimited
            default: return .needsMail
            }
        } catch {
            log("JetBox: help — request failed")
            return .needsMail
        }
    }
}

// MARK: - Диагностика

enum JetBoxDiagnostics {
    /// Маска почты для диагностики (запоминается при отправке письма входа).
    static let maskedEmailKey = "jetbox.loginEmailMasked"

    struct Facts: Equatable {
        var appVersion: String
        var osVersion: String
        var language: String
        var signIn: String
        var maskedEmail: String?
        var hasToken: Bool
        var tunnel: String
        var homeAnswers: Bool
        var latencyMs: Int?
        var route: String
        var uptime: String?
        var exit: String?
        var dns: String
    }

    static func text(_ facts: Facts, log: [String]) -> String {
        var lines = [
            "App: JetBox iOS \(facts.appVersion)",
            "iOS: \(facts.osVersion)",
            "Language: \(facts.language)",
            "Sign-in: \(facts.signIn)" + (facts.maskedEmail.map { ", \($0)" } ?? ""),
            "App token: \(facts.hasToken ? "yes" : "no")",
            "Tunnel: \(facts.tunnel)",
            "Home answers: " + (facts.homeAnswers ? "yes" + (facts.latencyMs.map { ", \($0) ms" } ?? "") : "no"),
            "Connection: \(facts.route)",
        ]
        if let uptime = facts.uptime { lines.append("Online for: \(uptime)") }
        if let exit = facts.exit { lines.append("Exit: \(exit)") }
        lines.append("DNS: \(facts.dns)")
        if !log.isEmpty {
            lines.append("")
            lines.append("Last \(log.count) JetBox log lines:")
            lines.append(contentsOf: log)
        }
        return lines.joined(separator: "\n")
    }

    /// `ab***@domain` — первые две буквы и домен.
    static func maskEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return "***" }
        return "\(parts[0].prefix(2))***@\(parts[1])"
    }

    // MARK: Журнал

    /// Последние `count` строк JetBox из журнала, уже без секретов.
    static func lastJetBoxLines(_ log: String, count: Int = 50) -> [String] {
        log.split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.contains("] JetBox") }
            .suffix(count)
            .map { scrub(String($0)) }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern)
    }

    private static let rules: [(NSRegularExpression, String)] = [
        // Параметры ссылки подключения и входа: ключ, подпись, токен, сервер.
        (regex(#"([#&?;](?:k|s|t|m|e|n|b|x)=)[^&\s"']*"#), "$1[hidden]"),
        // Адреса (management, API) — целиком.
        (regex(#"\b[a-zA-Z][a-zA-Z0-9+.-]*://[^\s"']+"#), "[url]"),
        // Почта — маской.
        (regex(#"\b([A-Za-z0-9._%+-]{1,2})[A-Za-z0-9._%+-]*@([A-Za-z0-9.-]+\.[A-Za-z]{2,})"#), "$1***@$2"),
        // Setup key и прочие UUID.
        (regex(#"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#), "[id]"),
        // Ключи WireGuard (base64, 32 байта) и подписи.
        (regex(#"[A-Za-z0-9+/]{42,}={0,2}"#), "[key]"),
        // Токены (base64url и hex от 24 символов).
        (regex(#"\b[A-Za-z0-9_-]{24,}\b"#), "[token]"),
        // IPv6.
        (regex(#"\b(?:[0-9A-Fa-f]{1,4}:){3,7}[0-9A-Fa-f]{1,4}\b"#), "[ipv6]"),
    ]

    private static let ipv4 = regex(#"\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\b"#)

    /// Убирает из строки журнала всё, что нельзя отдавать (§2 п.3).
    static func scrub(_ line: String) -> String {
        var text = line
        for (rule, template) in rules {
            text = rule.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                 withTemplate: template)
        }
        // Публичные IPv4 — маской; частные, CGNAT (меш) и метка канарейки — как есть.
        for match in ipv4.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let octets = String(text[range]).split(separator: ".").compactMap { Int($0) }
            if octets.count == 4, !isPrivate(octets) {
                text.replaceSubrange(range, with: "[ip]")
            }
        }
        return text
    }

    static func isPrivate(_ o: [Int]) -> Bool {
        switch (o[0], o[1]) {
        case (10, _), (127, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        case (100, 64...127): return true
        case (192, 0) where o[2] == 2: return true   // TEST-NET-1, метка канарейки
        default: return false
        }
    }

    /// Журнал приложения и расширения (AppLogger, общий контейнер App Group).
    static func readLog() -> String? {
        guard let dir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: GlobalConstants.userPreferencesSuiteName) else { return nil }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("swift-log.log")) else { return nil }
        return String(decoding: data.suffix(64 * 1024), as: UTF8.self)
    }

    // MARK: Письмо

    static func mailURL(to address: String, appVersion: String, message: String, diagnostics: String?) -> URL? {
        var body = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if let diagnostics, !diagnostics.isEmpty {
            body += "\n\n--- Diagnostics ---\n" + diagnostics
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [URLQueryItem(name: "subject", value: "JetBox: iOS \(appVersion)"),
                                 URLQueryItem(name: "body", value: String(body.prefix(6000)))]
        return components.url
    }
}
