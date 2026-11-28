//
//  JetBoxDNSCheck.swift
//  JetBox
//
//  Проверка «DNS идёт мимо JetBox» (1.0 (34), спека
//  VPN_Box/docs/superpowers/specs/2026-11-28-app-help-and-dns-check-design.md §3).
//
//  Фильтр рекламы и маршруты держатся на DNS коробки. DNS-профиль, DNS-приложение
//  или iCloud Private Relay тихо уводят запросы мимо, а iOS не даёт прочитать ни
//  чужие профили, ни Private Relay. Поэтому — проба канарейкой: коробка отвечает
//  на своё имя-канарейку (и на любой его поддомен) адресом-меткой 192.0.2.53,
//  публичных записей нет.
//
//  Два вопроса: (а) прямо DNS дома через туннель — знает ли коробка канарейку
//  (старая — молчим, без ложной тревоги); (б) системным резолвером, как браузер:
//  метка — DNS через коробку, другой ответ (и NXDOMAIN) — мимо, нет ответа —
//  только в диагностику. Сначала случайный поддомен (мимо кэша DNS iOS), при
//  пустом ответе — точное имя.
//

import Foundation
import Network

enum JetBoxDNSAnswer: Equatable {
    case addresses([String])
    case nxdomain
    case noAnswer

    var hasMark: Bool {
        if case .addresses(let list) = self { return list.contains(JetBoxDNSCheck.mark) }
        return false
    }
}

enum JetBoxDNSVerdict: Equatable {
    /// Системный DNS отвечает меткой коробки.
    case throughBox
    /// Коробка канарейку знает, а системный DNS — нет: запросы идут мимо.
    case bypassed
    /// Системный резолвер не ответил — только в диагностику.
    case noAnswer
    /// Коробка канарейку не знает (старая прошивка) — проверки нет.
    case boxDoesNotKnow

    /// Строка для диагностики (английский, не переводится).
    var diagnostics: String {
        switch self {
        case .throughBox: return "through JetBox"
        case .bypassed: return "bypasses JetBox"
        case .noAnswer: return "system resolver did not answer"
        case .boxDoesNotKnow: return "not checked (home does not answer the check name)"
        }
    }
}

enum JetBoxDNSCheck {
    /// Имя-канарейка рынка. В сборке США — только домены ai-boss.us; позже
    /// переедет в таблицу рынка (JETBOX_MARKET).
    #if JETBOX_US
    static let canaryName = "dnscheck.jetbox.ai-boss.us"
    #else
    static let canaryName = "dnscheck.jet-net.net"
    #endif
    /// Адрес-метка коробки (TEST-NET-1).
    static let mark = "192.0.2.53"
    /// Повтор, пока подключены.
    static let interval: TimeInterval = 600
    static let timeout: TimeInterval = 3

    struct Resolvers {
        /// Вопрос DNS дома (адрес, имя).
        var box: (String, String) async -> JetBoxDNSAnswer
        /// Вопрос системному резолверу.
        var system: (String) async -> JetBoxDNSAnswer

        static let live = Resolvers(box: { await askBox(host: $0, name: $1) },
                                    system: { await askSystem(name: $0) })
    }

    // MARK: - Чистая логика (JetBoxDNSCheckTests)

    static func randomNonce() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<12).map { _ in alphabet.randomElement()! })
    }

    static func nonceName(_ nonce: String) -> String { "\(nonce).\(canaryName)" }

    /// Ответ на случайное имя, а если в нём нет метки — на точное. Метка важнее
    /// всего, определённый ответ важнее молчания.
    static func combine(nonce first: JetBoxDNSAnswer, exact second: JetBoxDNSAnswer) -> JetBoxDNSAnswer {
        if second.hasMark || first == .noAnswer { return second }
        return first
    }

    static func verdict(box: JetBoxDNSAnswer, system: JetBoxDNSAnswer) -> JetBoxDNSVerdict {
        guard box.hasMark else { return .boxDoesNotKnow }
        if system.hasMark { return .throughBox }
        return system == .noAnswer ? .noAnswer : .bypassed
    }

    /// Целая проверка. `host` — DNS дома (тот же адрес, что у замера «До дома»).
    static func run(host: String, resolvers: Resolvers = .live,
                    nonce: String = randomNonce()) async -> JetBoxDNSVerdict {
        func ask(_ question: (String) async -> JetBoxDNSAnswer) async -> JetBoxDNSAnswer {
            let first = await question(nonceName(nonce))
            if first.hasMark { return first }
            return combine(nonce: first, exact: await question(canaryName))
        }
        let box = await ask { await resolvers.box(host, $0) }
        guard box.hasMark else { return .boxDoesNotKnow }
        let system = await ask(resolvers.system)
        return verdict(box: box, system: system)
    }

    /// Разбор ответа DNS на наш вопрос A: адреса, NXDOMAIN или «нет ответа»
    /// (чужой ID, обрезанный пакет, SERVFAIL и прочие коды).
    static func parseA(_ data: Data, id: UInt16) -> JetBoxDNSAnswer {
        let b = [UInt8](data)
        guard JetBoxHomeProbe.isAnswer(data, to: id) else { return .noAnswer }
        let rcode = b[3] & 0x0F
        if rcode == 3 { return .nxdomain }
        guard rcode == 0 else { return .noAnswer }
        let questions = Int(b[4]) << 8 | Int(b[5])
        let answers = Int(b[6]) << 8 | Int(b[7])
        var at = 12

        func skipName() -> Bool {
            while at < b.count {
                let len = Int(b[at])
                if len == 0 { at += 1; return true }
                if len & 0xC0 == 0xC0 { at += 2; return at <= b.count }
                at += 1 + len
            }
            return false
        }

        for _ in 0..<questions {
            guard skipName(), at + 4 <= b.count else { return .noAnswer }
            at += 4
        }
        var list: [String] = []
        for _ in 0..<answers {
            guard skipName(), at + 10 <= b.count else { break }
            let type = Int(b[at]) << 8 | Int(b[at + 1])
            let length = Int(b[at + 8]) << 8 | Int(b[at + 9])
            at += 10
            guard at + length <= b.count else { break }
            if type == 1, length == 4 {
                list.append(b[at..<at + 4].map(String.init).joined(separator: "."))
            }
            at += length
        }
        return .addresses(list)
    }

    // MARK: - Сеть

    /// Прямой вопрос A к DNS дома через туннель (UDP 53), один пакет.
    static func askBox(host: String, name: String) async -> JetBoxDNSAnswer {
        await withCheckedContinuation { (done: CheckedContinuation<JetBoxDNSAnswer, Never>) in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: 53, using: .udp)
            let queue = DispatchQueue(label: JetBoxIdentifiers.bundleID + ".dns-check")
            let id = UInt16.random(in: 1...UInt16.max)
            var finished = false

            func finish(_ answer: JetBoxDNSAnswer) {
                guard !finished else { return }
                finished = true
                connection.cancel()
                done.resume(returning: answer)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: JetBoxHomeProbe.query(id: id, name: name),
                                    completion: .contentProcessed { if $0 != nil { finish(.noAnswer) } })
                    connection.receiveMessage { data, _, _, error in
                        finish(data.map { error == nil ? parseA($0, id: id) : .noAnswer } ?? .noAnswer)
                    }
                case .failed, .cancelled: finish(.noAnswer)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(.noAnswer) }
        }
    }

    /// Вопрос системному резолверу — тот же путь, что у браузера.
    static func askSystem(name: String) async -> JetBoxDNSAnswer {
        await withCheckedContinuation { (done: CheckedContinuation<JetBoxDNSAnswer, Never>) in
            let lock = NSLock()
            var finished = false
            func finish(_ answer: JetBoxDNSAnswer) {
                lock.lock(); defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                done.resume(returning: answer)
            }
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo()
                hints.ai_family = AF_INET
                hints.ai_socktype = SOCK_STREAM
                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(name, nil, &hints, &result)
                defer { if let result { freeaddrinfo(result) } }
                guard status == 0 else {
                    finish(status == EAI_NONAME ? .nxdomain : .noAnswer)
                    return
                }
                var list: [String] = []
                var cursor = result
                while let info = cursor?.pointee {
                    if info.ai_family == AF_INET, let addr = info.ai_addr {
                        addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                            var inAddr = sin.pointee.sin_addr
                            if inet_ntop(AF_INET, &inAddr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                                list.append(String(cString: buffer))
                            }
                        }
                    }
                    cursor = info.ai_next
                }
                finish(.addresses(list))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(.noAnswer) }
        }
    }
}
