//
//  JetBoxHomeReadiness.swift
//  JetBox
//
//  «Подключено» — только когда дом отвечает (задача руководителя 22.11.2026,
//  сборка 1.0 (14)). Туннель iOS доложит .connected, как только ядро связалось
//  с сервером управления, а пир коробки поднимается ещё 1–2 минуты: проверяющий
//  Apple откроет http://192.168.60.10 и упрётся в таймаут Safari.
//
//  Поэтому экран «готово» и статус «подключено» ждут живого пира коробки:
//  состояние пира из ядра Connected или первый ответ DNS коробки на её
//  mesh-IP (как DnsProbe на Android). До этого — «Connecting…». Потолок — 90 с,
//  дальше показываем «подключено», как раньше, и пишем в журнал.
//

#if os(iOS)
import Foundation

@MainActor
final class JetBoxHomeReadiness: ObservableObject {
    static let shared = JetBoxHomeReadiness()

    static let timeout: TimeInterval = 90
    static let pollInterval: UInt64 = 1_500_000_000

    /// Дом ответил (или вышел потолок ожидания) при поднятом туннеле.
    @Published private(set) var isReady = false

    private var task: Task<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Что показывать: пока дом не ответил, «подключено» — ещё «подключаемся».
    nonisolated static func displayState(_ state: VPNDisplayState, homeReady: Bool) -> VPNDisplayState {
        state == .connected && !homeReady ? .connecting : state
    }

    func displayState(_ state: VPNDisplayState) -> VPNDisplayState {
        Self.displayState(state, homeReady: isReady)
    }

    /// Туннель сменил состояние: поднялся — ждём дом, упал — всё сначала.
    func tunnelStateChanged(_ state: VPNDisplayState, viewModel: ViewModel) {
        if state == .connected {
            start(viewModel: viewModel)
        } else {
            reset()
        }
    }

    /// Для сценария подключения: вернуться, когда дом ответил или вышел потолок.
    func waitUntilReady(viewModel: ViewModel) async {
        guard !isReady else { return }
        start(viewModel: viewModel)
        await withCheckedContinuation { waiters.append($0) }
    }

    private func start(viewModel: ViewModel) {
        guard !isReady, task == nil else { return }
        let adapter = viewModel.networkExtensionAdapter
        task = Task { [weak self] in
            let started = Date()
            var reason = "timeout"
            while !Task.isCancelled {
                let peers = await Self.fetchPeers(adapter)
                if Task.isCancelled { return }
                // Выход своей коробки должен быть — ждём и маршрут по умолчанию в туннеле.
                let exitOK = Self.exitReady(expected: JetBoxStore.allInternetHome,
                                            inTunnel: JetBoxTunnelState.defaultRouteInTunnel())
                if exitOK, let peer = Self.homePeer(in: peers) {
                    if Self.isConnected(peer) { reason = "box peer Connected"; break }
                    let ip = JetBoxHomeProbe.bareIP(peer.ip)
                    if !ip.isEmpty, await Self.dnsAnswers(ip) { reason = "box DNS answered"; break }
                }
                if Date().timeIntervalSince(started) >= Self.timeout { break }
                try? await Task.sleep(nanoseconds: Self.pollInterval)
            }
            guard !Task.isCancelled, let self else { return }
            let seconds = Int(Date().timeIntervalSince(started))
            if reason == "timeout" {
                AppLogger.shared.log("JetBox: home did not answer in \(seconds) s — showing connected by tunnel state; default route in tunnel: \(JetBoxTunnelState.defaultRouteInTunnel() ? "yes" : "no")")
            } else {
                AppLogger.shared.log("JetBox: home answers \(seconds) s after tunnel up (\(reason))")
            }
            self.finish()
        }
    }

    private func finish() {
        task = nil
        isReady = true
        resumeWaiters()
    }

    private func reset() {
        task?.cancel()
        task = nil
        if isReady { isReady = false }
        resumeWaiters()
    }

    private func resumeWaiters() {
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }

    // MARK: - Чистая логика (JetBoxHomeReadinessTests)

    /// Пир коробки: раздаёт выход в интернет, иначе — любой пир с маршрутами
    /// (сеть дома). Подключённый важнее простаивающего.
    nonisolated static func homePeer(in peers: [PeerInfo]) -> PeerInfo? {
        if let box = JetBoxLiveStats.boxPeer(in: peers) { return box }
        let routed = peers.filter { !$0.routes.isEmpty }
        return routed.first(where: isConnected) ?? routed.first
    }

    /// Выход не ожидается — не ждём; ожидается — только когда он в туннеле.
    nonisolated static func exitReady(expected: Bool, inTunnel: Bool) -> Bool {
        !expected || inTunnel
    }

    nonisolated static func isConnected(_ peer: PeerInfo) -> Bool {
        peer.connStatus.lowercased() == "connected"
    }

    // MARK: - Внутреннее

    /// Один запрос статуса у расширения. fetchData молча пропускает вызов,
    /// если предыдущий ещё в пути, — поэтому свой таймаут.
    private static func fetchPeers(_ adapter: NetworkExtensionAdapter) async -> [PeerInfo] {
        await withCheckedContinuation { (done: CheckedContinuation<[PeerInfo], Never>) in
            let once = Once()
            adapter.fetchData { details in once.run { done.resume(returning: details.peerInfo) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { once.run { done.resume(returning: []) } }
        }
    }

    private static func dnsAnswers(_ host: String) async -> Bool {
        await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            JetBoxHomeProbe.measure(host: host) { done.resume(returning: $0 != nil) }
        }
    }

    private final class Once {
        private var used = false
        private let lock = NSLock()
        func run(_ body: () -> Void) {
            lock.lock()
            let first = !used
            used = true
            lock.unlock()
            if first { body() }
        }
    }
}
#endif
