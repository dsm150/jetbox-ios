//
//  JetBoxLogin.swift
//  JetBox
//
//  Вход в приложение по email (сборка США, схема 22.11.2026 — спека
//  VPN_Box/docs/superpowers/specs/2026-11-21-partner-login-link-design.md,
//  раздел «Вход в приложение по email — рабочая схема»).
//
//  1. Экран email → POST /api/app/v1/login/request — всегда 202, есть такой
//     адрес или нет (429 — лимит).
//  2. Письмо со ссылкой https://jetbox.ai-boss.us/auth/verify#t=<токен>.
//     Токен во фрагменте: на сервер сайта он не уходит.
//  3. Приложение меняет токен на параметры подключения:
//     POST /api/app/v1/login/verify → 200 {connect_url, …}; 410 — ссылка
//     устарела или использована, 409 device_limit, 429 — лимит.
//  3а. Запасной путь (и вход проверяющего Apple без почты): «Enter code
//     manually» → 6 цифр из письма → POST login/verify {email, code, …};
//     401 bad_code с остатком попыток, 410 — код истёк или попытки кончились.
//  4. connect_url идёт в тот же разбор, что ссылка /connect из Кабинета:
//     маска сервера, проверка ключа и дальше обычный сценарий подключения.
//
//  Токен и setup key не пишутся в журнал нигде: в журнал идут только
//  коды ответа.
//

import Foundation

extension JetBoxConfig {
    /// Сайт партнёра: на нём лежит AASA для `/auth/verify` и `/auth/*`.
    static var loginLinkHost: String { JetBoxServers.loginLinkHost }
    static let loginLinkPath = "/auth/verify"
    /// API приложения в Кабинете. Сайт партнёра токенов и ключей не видит.
    /// Адрес — по редакции (Config/JetBoxEdition.xcconfig → Info.plist).
    static var loginAPIBase: URL { URL(string: JetBoxServers.apiBaseURL) ?? URL(string: "https://invalid.invalid/")! }
    /// Не чаще одного письма в минуту с одного экрана (лимит Кабинета строже
    /// по сумме: 5 на адрес за 10 минут).
    static let loginResendInterval: TimeInterval = 60
}

// MARK: - Ссылка из письма

enum JetBoxLoginLink {
    enum Outcome: Equatable {
        case token(String)
        /// Наша ссылка входа, но без токена или с испорченным токеном.
        case broken
        case notOurs
    }

    /// `anyHost` (сборка США, JetBoxLinkRules): хост ссылки не проверяем —
    /// токен всё равно уходит только в API приложения.
    static func parse(_ url: URL, anyHost: Bool = JetBoxLinkRules.editionAcceptsAnyHost) -> Outcome {
        guard url.scheme?.lowercased() == "https",
              anyHost || url.host?.lowercased() == JetBoxConfig.loginLinkHost else { return .notOurs }
        var path = url.path.lowercased()
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        // Остальные пути `/auth/*` — страницы сайта, не наши.
        guard path == JetBoxConfig.loginLinkPath else { return .notOurs }

        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment,
              !fragment.isEmpty else { return .broken }
        for pair in fragment.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].lowercased() == "t" else { continue }
            let raw = String(parts[1])
            let value = (raw.removingPercentEncoding ?? raw).trimmingCharacters(in: .whitespacesAndNewlines)
            return isValidToken(value) ? .token(value) : .broken
        }
        return .broken
    }

    /// Формат токена Кабинет не обещает; принимаем URL-безопасные символы
    /// разумной длины, всё прочее — испорченная ссылка, в сеть не идём.
    static func isValidToken(_ token: String) -> Bool {
        guard (16...512).contains(token.count) else { return false }
        return token.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "-_.~".unicodeScalars.contains(scalar))
        }
    }
}

// MARK: - Адрес почты

enum JetBoxEmail {
    static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Простая проверка до отправки — как на сайте: что-то@что-то.зона.
    static func isValid(_ raw: String) -> Bool {
        let email = normalized(raw)
        guard email.count <= 254 else { return false }
        return email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s.]{2,}$"#, options: .regularExpression) != nil
    }
}

// MARK: - API Кабинета

struct JetBoxLoginAPI {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    enum RequestOutcome: Equatable {
        case sent
        case rateLimited
        case offline
        case unavailable
    }

    enum VerifyOutcome: Equatable {
        case connect(URL)
        /// Неверный код (401 bad_code), сколько попыток осталось — если Кабинет сказал.
        case badCode(attemptsLeft: Int?)
        case expired
        case deviceLimit
        case rateLimited
        case offline
        case unavailable
    }

    var base: URL = JetBoxConfig.loginAPIBase
    var transport: Transport = { try await JetBoxLoginAPI.session.data(for: $0) }
    /// Журнал. Сюда уходят только коды ответа — ни токена, ни ключа.
    var log: (String) -> Void = { AppLogger.shared.log($0) }
    /// Токен приложения из verify (для «Delete account») — в Keychain этого
    /// устройства. Ответ без токена стирает прежний: он от другого входа.
    var storeAppToken: (String?) -> Void = { token in
        if let token { JetBoxAppToken.save(token) } else { JetBoxAppToken.delete() }
    }

    /// Без кэша и cookie: ответы с ключом на диск не ложатся.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// Язык письма: сборка США — английский всегда, русская — по языку телефона.
    static func mailLanguage(homeOnly: Bool = JetBoxEdition.homeOnly,
                             preferred: [String] = Locale.preferredLanguages) -> String {
        if homeOnly { return "en" }
        return preferred.first?.lowercased().hasPrefix("ru") == true ? "ru" : "en"
    }

    func requestLink(email: String, language: String = JetBoxLoginAPI.mailLanguage()) async -> RequestOutcome {
        let body = ["email": JetBoxEmail.normalized(email), "lang": language, "platform": "ios"]
        switch await post("login/request", body) {
        case .response(let code, _) where (200...299).contains(code):
            log("JetBox: email login — link request accepted (\(code))")
            return .sent
        case .response(429, _):
            log("JetBox: email login — request limit (429)")
            return .rateLimited
        case .response(let code, _):
            log("JetBox: email login — server answered \(code) to link request")
            return .unavailable
        case .offline:
            return .offline
        case .failed:
            return .unavailable
        }
    }

    func verify(token: String, deviceName: String) async -> VerifyOutcome {
        await verify(["token": token, "device_name": deviceName, "platform": "ios"])
    }

    /// Код из письма, введённый руками (и демо-вход проверяющего Apple).
    func verify(email: String, code: String, deviceName: String) async -> VerifyOutcome {
        await verify(["email": JetBoxEmail.normalized(email), "code": code,
                      "device_name": deviceName, "platform": "ios"])
    }

    /// Код из письма: ровно 6 цифр. Всё лишнее (пробелы, дефис) отбрасываем.
    static func normalizedCode(_ raw: String) -> String {
        String(raw.filter { $0.isASCII && $0.isNumber }.prefix(6))
    }

    private func verify(_ body: [String: String]) async -> VerifyOutcome {
        switch await post("login/verify", body) {
        case .response(200, let data):
            guard let url = Self.connectURL(from: data) else {
                log("JetBox: email login — response without connection details")
                return .unavailable
            }
            let token = Self.appToken(from: data)
            storeAppToken(token)
            log("JetBox: email login — verified (200), app token: \(token == nil ? "no" : "yes")")
            return .connect(url)
        case .response(410, _):
            log("JetBox: email login — link expired or used (410)")
            return .expired
        case .response(401, let data):
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let left = (json?["attempts_left"] as? NSNumber)?.intValue
            log("JetBox: email login — wrong code (401), attempts left: \(left.map(String.init) ?? "?")")
            return .badCode(attemptsLeft: left)
        case .response(409, let data):
            let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            log("JetBox: email login — refused 409 (\(error ?? "no code"))")
            return error == "device_limit" ? .deviceLimit : .unavailable
        case .response(429, _):
            log("JetBox: email login — verify limit (429)")
            return .rateLimited
        case .response(let code, _):
            log("JetBox: email login — server answered \(code) to verify")
            return .unavailable
        case .offline:
            return .offline
        case .failed:
            return .unavailable
        }
    }

    /// Ссылка подключения из ответа verify. Основной путь — готовый
    /// `connect_url`; без него собираем ту же ссылку из полей. В обоих
    /// случаях дальше её проверяет `JetBoxLink.parse`: ключ и формат `m`
    /// (маска сервера — только в русской сборке).
    static func connectURL(from data: Data) -> URL? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // 1.0 (21): mesh-адрес пира коробки — параметром `b` той же ссылки.
        let boxParam = JetBoxLink.validIP(json["box_ip"] as? String).map { "&b=" + escape($0) } ?? ""
        if let raw = json["connect_url"] as? String, let url = URL(string: raw),
           case .payload = JetBoxLink.parse(url) {
            return boxParam.isEmpty ? url : (URL(string: raw + boxParam) ?? url)
        }
        guard let key = json["setup_key"] as? String, !key.isEmpty else { return nil }
        var fragment = "k=" + escape(key)
        if let management = json["management_url"] as? String, !management.isEmpty {
            fragment += "&m=" + escape(management)
        }
        if let exit = json["exit_node"] as? String, !exit.isEmpty { fragment += "&e=" + escape(exit) }
        if let name = json["site_name"] as? String, !name.isEmpty { fragment += "&n=" + escape(name) }
        fragment += boxParam
        return URL(string: "\(JetBoxConfig.customScheme)://connect#\(fragment)")
    }

    // MARK: Внутреннее

    private enum Reply {
        case response(Int, Data)
        case offline
        case failed
    }

    private func post(_ path: String, _ body: [String: String]) async -> Reply {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        do {
            let (data, response) = try await transport(request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            return .response(http.statusCode, data)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            log("JetBox: email login — server unreachable (\(error.code.rawValue))")
            return .offline
        } catch {
            // Текст ошибки не пишем: в нём бывает URL, а URL здесь без секретов,
            // но правило «только коды» проще держать без исключений.
            log("JetBox: email login — request failed")
            return .failed
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
        .internationalRoamingOff, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed
    ]

    private static func escape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

// MARK: - Экран email: состояние

@MainActor
final class JetBoxLoginModel: ObservableObject {
    enum Phase: Equatable {
        case enter
        case sending
        case sent(email: String)
        /// «Enter code manually»: 6 цифр из письма.
        case code(email: String)
    }

    @Published var email = ""
    @Published var code = ""
    @Published private(set) var isVerifying = false
    @Published private(set) var phase: Phase = .enter
    /// Текст под полем или под кнопкой: неверный адрес, лимит, нет сети.
    @Published private(set) var message: String?
    /// «Отправили ещё раз» на пару секунд после повторной отправки.
    @Published private(set) var resentNote = false
    @Published private(set) var lastSentAt: Date?

    var api = JetBoxLoginAPI()
    var now: () -> Date = Date.init
    var deviceName: () -> String = { Device.getName() }
    /// Код подтверждён: ссылку подключения забирает сценарий (JetBoxOnboarding).
    var onConnect: @MainActor (URL) -> Void = { _ in }

    var isSending: Bool { phase == .sending }

    private var sentAddress: String? {
        switch phase {
        case .sent(let address), .code(let address): return address
        case .enter, .sending: return nil
        }
    }

    /// Сколько секунд осталось до «Отправить ещё раз».
    func resendWait(at date: Date) -> Int {
        guard let lastSentAt else { return 0 }
        let left = JetBoxConfig.loginResendInterval - date.timeIntervalSince(lastSentAt)
        return left > 0 ? Int(left.rounded(.up)) : 0
    }

    func submit() async {
        guard !isSending else { return }
        let address = JetBoxEmail.normalized(email)
        guard JetBoxEmail.isValid(address) else {
            message = JBText.loginInvalidEmail
            return
        }
        email = address
        message = nil
        phase = .sending
        let outcome = await api.requestLink(email: address)
        apply(outcome, address: address, previous: .enter)
    }

    func resend() async {
        guard let address = sentAddress, resendWait(at: now()) == 0 else { return }
        let back = phase
        message = nil
        phase = .sending
        let outcome = await api.requestLink(email: address)
        apply(outcome, address: address, previous: back)
        if outcome == .sent {
            if case .code = back {
                phase = back
                code = ""
            }
            flashResent()
        }
    }

    func useAnotherEmail() {
        phase = .enter
        message = nil
        code = ""
        resentNote = false
    }

    /// После «Sign out»: форма как у свежей установки.
    /// Сообщение на чистом экране входа (после «Delete account» без токена).
    func showNotice(_ text: String) {
        message = text
    }

    func reset() {
        phase = .enter
        email = ""
        code = ""
        message = nil
        resentNote = false
        lastSentAt = nil
        isVerifying = false
    }

    func enterCodeManually() {
        guard case .sent(let address) = phase else { return }
        message = nil
        code = ""
        phase = .code(email: address)
    }

    func backToLink() {
        guard case .code(let address) = phase else { return }
        message = nil
        phase = .sent(email: address)
    }

    /// Поле кода: только цифры, не больше шести; шесть — сразу проверяем
    /// (так срабатывает и автоподстановка кода iOS).
    func codeChanged() {
        let clean = JetBoxLoginAPI.normalizedCode(code)
        if clean != code { code = clean }
        if clean.count == 6, !isVerifying { Task { await submitCode() } }
    }

    func submitCode() async {
        guard case .code(let address) = phase, !isVerifying else { return }
        let digits = JetBoxLoginAPI.normalizedCode(code)
        guard digits.count == 6 else { return }
        message = nil
        isVerifying = true
        let outcome = await api.verify(email: address, code: digits, deviceName: deviceName())
        isVerifying = false
        switch outcome {
        case .connect(let url):
            code = ""
            onConnect(url)
        case .badCode(let left):
            code = ""
            message = left.map(JBText.loginCodeWrongLeft) ?? JBText.loginCodeWrong
        case .expired:
            code = ""
            message = JBText.loginCodeExpired
        case .deviceLimit:
            message = JBText.errDeviceLimitBody
        case .rateLimited:
            message = JBText.loginRateLimited
        case .offline:
            message = JBText.loginOffline
        case .unavailable:
            message = JBText.loginUnavailable
        }
    }

    private func apply(_ outcome: JetBoxLoginAPI.RequestOutcome, address: String, previous: Phase) {
        switch outcome {
        case .sent:
            lastSentAt = now()
            phase = .sent(email: address)
        case .rateLimited:
            message = JBText.loginRateLimited
            phase = previous
        case .offline:
            message = JBText.loginOffline
            phase = previous
        case .unavailable:
            message = JBText.loginUnavailable
            phase = previous
        }
    }

    private func flashResent() {
        resentNote = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            self?.resentNote = false
        }
    }
}

#if DEBUG
extension JetBoxLoginModel {
    /// Только для съёмки: `-JetBoxLoginDemo enter|sent|error`.
    static var demoRequested: Bool { UserDefaults.standard.string(forKey: "JetBoxLoginDemo") != nil }

    func applyDemoIfRequested() {
        switch UserDefaults.standard.string(forKey: "JetBoxLoginDemo") {
        case "sent":
            email = "alex@example.com"
            lastSentAt = now().addingTimeInterval(-18)
            phase = .sent(email: email)
        case "error":
            email = "alex@example"
            message = JBText.loginInvalidEmail
        case "code":
            email = "alex@example.com"
            lastSentAt = now().addingTimeInterval(-18)
            phase = .code(email: email)
        case "badcode":
            email = "alex@example.com"
            lastSentAt = now().addingTimeInterval(-75)
            phase = .code(email: email)
            message = JBText.loginCodeWrongLeft(2)
        default:
            break
        }
    }
}
#endif
