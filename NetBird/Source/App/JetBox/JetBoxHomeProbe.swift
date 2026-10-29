//
//  JetBoxHomeProbe.swift
//  JetBox
//
//  «До дома» — время ответа DNS на самом JetBox через туннель.
//
//  Почему не цифра от ядра: NetBird меряет задержку один раз, при установке
//  прямого (ICE) соединения, и никогда — через ретранслятор. Почему DNS, а не
//  пинг: DNS JetBox клиенту открыт всегда (через него работает блокировка
//  рекламы), а ICMP от устройства к JetBox политики NetBird не пропускают
//  (правила sv-jetnet-access-* — от JetBox к устройствам). Берём минимум из
//  трёх запросов подряд: первый может уйти к внешнему резолверу, повторы
//  отвечаются из кэша — это и есть дорога до дома.
//

import Foundation
import Network

enum JetBoxHomeProbe {
    static let samples = 3
    static let timeout: TimeInterval = 1.5
    static let probeName = "jet-net.net"

    /// Меряет и отдаёт результат (мс) на главной очереди; nil — не ответил.
    static func measure(host: String, completion: @escaping (Int?) -> Void) {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: 53, using: .udp)
        let queue = DispatchQueue(label: "net.jetnet.jetbox.home-probe")
        var results: [Int] = []
        var finished = false

        func finish() {
            guard !finished else { return }
            finished = true
            connection.cancel()
            let best = results.min()
            DispatchQueue.main.async { completion(best) }
        }

        func ask(_ remaining: Int) {
            guard remaining > 0, !finished else { return finish() }
            let id = UInt16.random(in: 1...UInt16.max)
            let started = DispatchTime.now()
            connection.send(content: query(id: id, name: probeName), completion: .contentProcessed { error in
                if error != nil { finish() }
            })
            connection.receiveMessage { data, _, _, error in
                if let data, error == nil, isAnswer(data, to: id) {
                    let ns = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
                    results.append(max(1, Int((Double(ns) / 1_000_000).rounded())))
                }
                ask(remaining - 1)
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: ask(samples)
            case .failed, .cancelled: finish()
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout * Double(samples)) { finish() }
    }

    // MARK: - Чистая логика (JetBoxHomeProbeTests)

    /// Рекурсивный запрос A-записи — стандартный DNS-вопрос.
    static func query(id: UInt16, name: String) -> Data {
        var bytes: [UInt8] = [UInt8(id >> 8), UInt8(id & 0xFF), 0x01, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
        for label in name.split(separator: ".") {
            bytes.append(UInt8(label.utf8.count))
            bytes.append(contentsOf: label.utf8)
        }
        bytes.append(contentsOf: [0x00, 0x00, 0x01, 0x00, 0x01])
        return Data(bytes)
    }

    /// Ответ на наш вопрос: тот же ID и бит QR. Любой код ответа годится —
    /// нам нужно время, а не запись.
    static func isAnswer(_ data: Data, to id: UInt16) -> Bool {
        let b = [UInt8](data)
        return b.count >= 12 && b[0] == UInt8(id >> 8) && b[1] == UInt8(id & 0xFF) && (b[2] & 0x80) != 0
    }

    /// Адрес пира бывает с маской («100.79.148.91/16»).
    static func bareIP(_ address: String) -> String {
        String(address.split(separator: "/").first ?? Substring(address))
    }
}

/// JetBox ведёт через дом весь интернет телефона. Принудительный ретранслятор
/// апстрима (на iPhone включён по умолчанию ради батареи) гнал бы всё видео
/// клиентов через наш сервер, а пинг и скорость были бы хуже. Решение
/// владельца 24.10.2026: по умолчанию — напрямую; NetBird сам уйдёт на
/// ретранслятор, если сеть не пускает. Ставим один раз: если клиент потом
/// включит ретранслятор в расширенных настройках, его выбор не трогаем.
enum JetBoxConnectionDefaults {
    static let appliedKey = "jetbox.directByDefaultApplied"

    static func applyDirectByDefaultIfNeeded(
        defaults: UserDefaults? = UserDefaults(suiteName: GlobalConstants.userPreferencesSuiteName)
    ) {
        guard let defaults, !defaults.bool(forKey: appliedKey) else { return }
        defaults.set(false, forKey: GlobalConstants.keyForceRelayConnection)
        defaults.set(true, forKey: appliedKey)
    }
}

/// Всё, что JetBox делает при запуске приложения, — одной строкой во врезке.
enum JetBoxStartup {
    static func run() {
        JetBoxAdvancedAccess.migrateLegacyFlagIfNeeded()
        JetBoxConnectionDefaults.applyDirectByDefaultIfNeeded()
    }
}
