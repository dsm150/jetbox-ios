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

final class JetBoxLiveStats: ObservableObject {
    static let shared = JetBoxLiveStats()

    struct Snapshot: Equatable {
        var latencyMs: Int?
        var relayed: Bool
        var bytesRx: Int64
        var bytesTx: Int64
    }

    @Published private(set) var box: Snapshot?
    /// Когда поднят туннель — от системы, а не от нас: переживает перезапуск
    /// приложения.
    @Published private(set) var connectedSince: Date?

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
        } else {
            probedLatencyMs = nil
        }
        let snapshot = peer.map {
            Snapshot(latencyMs: probedLatencyMs ?? Self.latencyMs($0.latency), relayed: $0.relayed,
                     bytesRx: $0.bytesRx, bytesTx: $0.bytesTx)
        }
        if snapshot != box { box = snapshot }
        if connectedSince != self.connectedSince { self.connectedSince = connectedSince }
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
