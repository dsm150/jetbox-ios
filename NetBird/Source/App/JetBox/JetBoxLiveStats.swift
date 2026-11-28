//
//  JetBoxLiveStats.swift
//  JetBox
//
//  Живые показатели подключения к JetBox для нижней панели: пинг до дома,
//  как идёт соединение, трафик, время в сети.
//
//  Апстрим опрашивает расширение раз в 10 с, но наружу публикует пиров,
//  только когда меняется их состояние, — пинг и трафик так не обновляются.
//  Одна врезка в MainViewModel.startPollingDetails отдаёт сюда каждый ответ.
//

import Foundation
import Combine
import Network

final class JetBoxLiveStats: ObservableObject {
    static let shared = JetBoxLiveStats()

    struct Snapshot: Equatable {
        var latencyMs: Int?
        var relayed: Bool
        var bytesRx: Int64
        var bytesTx: Int64
        /// Пир JetBox в состоянии Connected (ядро соединилось с ним).
        var connected: Bool = true
    }

    /// Как идёт соединение с JetBox — строка Connection в панели и деталях.
    enum Route: Equatable {
        case direct
        case relayed
        /// Сборка США: relay выключен в ядре (NB_DISABLE_RELAY), и если прямое
        /// соединение не вышло — так и пишем, а не «Relay».
        case notDirect
    }

    static func route(_ snapshot: Snapshot, relayAllowed: Bool = !JetBoxEdition.homeOnly) -> Route {
        guard relayAllowed else {
            return snapshot.connected && !snapshot.relayed ? .direct : .notDirect
        }
        return snapshot.relayed ? .relayed : .direct
    }

    @Published private(set) var box: Snapshot?
    /// Когда поднят туннель — от системы, а не от нас: переживает перезапуск
    /// приложения.
    @Published private(set) var connectedSince: Date?
    /// Маршрут по умолчанию в применённых настройках туннеля (JetBoxTunnelState):
    /// меняется — главный экран перерисовывает «Protected» / предупреждение.
    @Published private(set) var defaultRouteInTunnel = false

    /// Проба DNS канарейкой (1.0 (34)): nil — ещё не проверяли в этом подключении.
    @Published private(set) var dnsVerdict: JetBoxDNSVerdict?
    /// Когда проверяли; nil — проверить при первом удобном ответе расширения
    /// (новое подключение, смена сети).
    private var lastDNSCheck: Date?
    private var dnsChecking = false
    /// Подменяется в тестах; по умолчанию — настоящая проба.
    var runDNSCheck: (String) async -> JetBoxDNSVerdict = { await JetBoxDNSCheck.run(host: $0) }
    private let pathMonitor = NWPathMonitor()
    private var pathSeen = false

    init() {
        // Смена сети (Wi-Fi ↔ сотовая, другой Wi-Fi) — проверить заново.
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.pathSeen { self.lastDNSCheck = nil }
                self.pathSeen = true
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: JetBoxIdentifiers.bundleID + ".path"))
    }

    /// Последний замер «до дома» (JetBoxHomeProbe). Ядро меряет задержку
    /// только на прямом соединении — его цифра идёт лишь запасной.
    private var probedLatencyMs: Int?
    private var probing = false

    /// Каждый ответ расширения о статусе (раз в 10 с, пока приложение
    /// открыто). Зовётся на главной очереди.
    func ingest(_ details: StatusDetails, connectedSince: Date?) {
        let peer = Self.boxPeer(in: details.peerInfo)
        if let peer, peer.connStatus.lowercased() == "connected" {
            probe(host: JetBoxHomeProbe.bareIP(peer.ip))
            checkDNSIfDue(host: JetBoxHomeProbe.bareIP(peer.ip))
        } else {
            probedLatencyMs = nil
            // Новое подключение — новая проверка (spec §3: «при „Под защитой“»).
            lastDNSCheck = nil
        }
        let snapshot = peer.map {
            Snapshot(latencyMs: probedLatencyMs ?? Self.latencyMs($0.latency), relayed: $0.relayed,
                     bytesRx: $0.bytesRx, bytesTx: $0.bytesTx,
                     connected: $0.connStatus.lowercased() == "connected")
        }
        if snapshot != box { box = snapshot }
        if connectedSince != self.connectedSince { self.connectedSince = connectedSince }
        let inTunnel = JetBoxTunnelState.defaultRouteInTunnel()
        if inTunnel != defaultRouteInTunnel { defaultRouteInTunnel = inTunnel }
    }

    private func probe(host: String) {
        guard !probing else { return }
        probing = true
        JetBoxHomeProbe.measure(host: host) { [weak self] ms in
            guard let self else { return }
            self.probing = false
            self.probedLatencyMs = ms
            if let ms, var current = self.box, current.latencyMs != ms {
                current.latencyMs = ms
                self.box = current
            }
        }
    }

    /// Раз в 10 минут, после нового подключения и после смены сети.
    func checkDNSIfDue(host: String, now: Date = Date()) {
        guard !dnsChecking else { return }
        if let last = lastDNSCheck, now.timeIntervalSince(last) < JetBoxDNSCheck.interval { return }
        dnsChecking = true
        lastDNSCheck = now
        let run = runDNSCheck
        Task { @MainActor [weak self] in
            let verdict = await run(host)
            guard let self else { return }
            self.dnsChecking = false
            AppLogger.shared.log("JetBox: DNS check — \(verdict.diagnostics)")
            if verdict != self.dnsVerdict { self.dnsVerdict = verdict }
        }
    }

    // MARK: - Чистая логика (JetBoxLiveStatsTests)

    static let exitRoutes: Set<String> = ["0.0.0.0/0", "::/0"]

    /// JetBox — тот пир, который раздаёт выход в интернет. Подключённый важнее
    /// простаивающего: при смене коробки старый пир какое-то время ещё виден.
    static func boxPeer(in peers: [PeerInfo]) -> PeerInfo? {
        let exits = peers.filter { $0.routes.contains(where: exitRoutes.contains) }
        return exits.first(where: { $0.connStatus.lowercased() == "connected" }) ?? exits.first
    }

    /// Пинг из строки длительности Go («12.3ms», «850µs», «1.2s»).
    /// «0s» — значит, ядро ещё не мерило: показываем прочерк, а не ноль.
    static func latencyMs(_ raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let units: [(suffix: String, toMs: Double)] = [("ns", 1e-6), ("µs", 1e-3), ("us", 1e-3), ("ms", 1), ("s", 1000)]
        for unit in units where text.hasSuffix(unit.suffix) {
            guard let value = Double(text.dropLast(unit.suffix.count)) else { return nil }
            let ms = value * unit.toMs
            return ms > 0 ? max(1, Int(ms.rounded())) : nil
        }
        return nil
    }

    /// «4:05» до часа, «1:04:05» после.
    static func uptime(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = s % 3600 / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
