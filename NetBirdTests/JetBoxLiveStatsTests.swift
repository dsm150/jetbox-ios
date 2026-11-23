//
//  JetBoxLiveStatsTests.swift
//  NetBirdTests
//
//  Живые показатели нижней панели: какой пир — JetBox, как читается пинг из
//  строки Go и как пишется время в сети.
//

import XCTest
import NetBirdSDK
@testable import NetBird

final class JetBoxLiveStatsTests: XCTestCase {

    private func peer(_ name: String, status: String = "Connected", routes: [String] = [],
                      latency: String = "0s", relayed: Bool = false) -> PeerInfo {
        PeerInfo(ip: "100.64.0.1", fqdn: name, localIceCandidateEndpoint: "", remoteIceCandidateEndpoint: "",
                 localIceCandidateType: "", remoteIceCandidateType: "", pubKey: "", latency: latency,
                 bytesRx: 0, bytesTx: 0, connStatus: status, connStatusUpdate: "", direct: !relayed,
                 lastWireguardHandshake: "", relayed: relayed, rosenpassEnabled: false, routes: routes)
    }

    func testBoxIsThePeerThatCarriesTheExitRoute() {
        let peers = [peer("laptop"), peer("box", routes: ["192.168.1.0/24", "0.0.0.0/0"]), peer("nas")]
        XCTAssertEqual(JetBoxLiveStats.boxPeer(in: peers)?.fqdn, "box")
    }

    func testIPv6ExitRouteCountsToo() {
        XCTAssertEqual(JetBoxLiveStats.boxPeer(in: [peer("box6", routes: ["::/0"])])?.fqdn, "box6")
    }

    func testConnectedExitWinsOverIdleOne() {
        let peers = [peer("old", status: "Idle", routes: ["0.0.0.0/0"]),
                     peer("live", status: "Connected", routes: ["0.0.0.0/0"])]
        XCTAssertEqual(JetBoxLiveStats.boxPeer(in: peers)?.fqdn, "live")
    }

    func testNoExitRouteMeansNoBox() {
        XCTAssertNil(JetBoxLiveStats.boxPeer(in: [peer("laptop", routes: ["10.0.0.0/8"])]))
        XCTAssertNil(JetBoxLiveStats.boxPeer(in: []))
    }

    func testLatencyFromGoDuration() {
        XCTAssertEqual(JetBoxLiveStats.latencyMs("12.345ms"), 12)
        XCTAssertEqual(JetBoxLiveStats.latencyMs("24.6ms"), 25)
        XCTAssertEqual(JetBoxLiveStats.latencyMs("1.2s"), 1200)
        XCTAssertEqual(JetBoxLiveStats.latencyMs("850µs"), 1)
        XCTAssertEqual(JetBoxLiveStats.latencyMs("850us"), 1)
    }

    func testUnknownLatencyIsNil() {
        XCTAssertNil(JetBoxLiveStats.latencyMs("0s"))
        XCTAssertNil(JetBoxLiveStats.latencyMs(""))
        XCTAssertNil(JetBoxLiveStats.latencyMs("1m2.5s"))
        XCTAssertNil(JetBoxLiveStats.latencyMs("n/a"))
    }

    func testUptimeFormatting() {
        XCTAssertEqual(JetBoxLiveStats.uptime(0), "0:00")
        XCTAssertEqual(JetBoxLiveStats.uptime(65), "1:05")
        XCTAssertEqual(JetBoxLiveStats.uptime(3_725), "1:02:05")
        XCTAssertEqual(JetBoxLiveStats.uptime(-5), "0:00")
    }
}

/// «До дома» меряем сами — временем ответа DNS на JetBox через туннель.
final class JetBoxHomeProbeTests: XCTestCase {

    func testQueryIsAStandardRecursiveAQuestion() {
        let q = [UInt8](JetBoxHomeProbe.query(id: 0xBEEF, name: "jet-net.net"))
        XCTAssertEqual(Array(q[0..<12]), [0xBE, 0xEF, 0x01, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
        let name: [UInt8] = [7] + Array("jet-net".utf8) + [3] + Array("net".utf8) + [0]
        XCTAssertEqual(Array(q[12..<(12 + name.count)]), name)
        XCTAssertEqual(Array(q.suffix(4)), [0x00, 0x01, 0x00, 0x01])
    }

    func testOnlyAResponseWithOurIdCounts() {
        var reply = [UInt8](JetBoxHomeProbe.query(id: 0x1234, name: "jet-net.net"))
        reply[2] |= 0x80 // QR: ответ
        XCTAssertTrue(JetBoxHomeProbe.isAnswer(Data(reply), to: 0x1234))
        XCTAssertFalse(JetBoxHomeProbe.isAnswer(Data(reply), to: 0x1235))
        XCTAssertFalse(JetBoxHomeProbe.isAnswer(JetBoxHomeProbe.query(id: 0x1234, name: "jet-net.net"), to: 0x1234))
        XCTAssertFalse(JetBoxHomeProbe.isAnswer(Data([0x12, 0x34]), to: 0x1234))
    }

    func testPeerAddressWithoutMask() {
        XCTAssertEqual(JetBoxHomeProbe.bareIP("100.64.10.20/16"), "100.64.10.20")
        XCTAssertEqual(JetBoxHomeProbe.bareIP("100.64.10.20"), "100.64.10.20")
    }
}

/// JetBox ведёт через дом весь интернет телефона — по умолчанию напрямую,
/// а не через ретранслятор апстрима. Выбор клиента после этого не трогаем.
final class JetBoxConnectionDefaultsTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "JetBoxConnectionDefaultsTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testFirstRunTurnsForcedRelayOff() {
        defaults.set(true, forKey: GlobalConstants.keyForceRelayConnection)
        JetBoxConnectionDefaults.applyDirectByDefaultIfNeeded(defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: GlobalConstants.keyForceRelayConnection))
    }

    func testClientsLaterChoiceSurvives() {
        JetBoxConnectionDefaults.applyDirectByDefaultIfNeeded(defaults: defaults)
        defaults.set(true, forKey: GlobalConstants.keyForceRelayConnection) // включил сам
        JetBoxConnectionDefaults.applyDirectByDefaultIfNeeded(defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: GlobalConstants.keyForceRelayConnection))
    }
}

/// Строка Connection: в сборке США relay выключен в ядре (этап 1) — либо
/// Direct, либо «Can't reach your JetBox directly», но не Relay.
final class JetBoxRouteTests: XCTestCase {

    private func snapshot(connected: Bool, relayed: Bool) -> JetBoxLiveStats.Snapshot {
        JetBoxLiveStats.Snapshot(latencyMs: nil, relayed: relayed, bytesRx: 0, bytesTx: 0, connected: connected)
    }

    func testWithoutRelayConnectedDirectIsDirect() {
        XCTAssertEqual(JetBoxLiveStats.route(snapshot(connected: true, relayed: false), relayAllowed: false), .direct)
    }

    func testWithoutRelayNotConnectedSaysNotDirect() {
        XCTAssertEqual(JetBoxLiveStats.route(snapshot(connected: false, relayed: false), relayAllowed: false),
                       .notDirect)
    }

    func testWithoutRelayNeverSaysRelayed() {
        XCTAssertEqual(JetBoxLiveStats.route(snapshot(connected: true, relayed: true), relayAllowed: false),
                       .notDirect)
    }

    func testWithRelayKeepsRelayed() {
        XCTAssertEqual(JetBoxLiveStats.route(snapshot(connected: true, relayed: true), relayAllowed: true), .relayed)
        XCTAssertEqual(JetBoxLiveStats.route(snapshot(connected: true, relayed: false), relayAllowed: true), .direct)
    }

    func testIngestMarksDisconnectedBoxPeer() {
        let stats = JetBoxLiveStats()
        let details = StatusDetails(ip: "", fqdn: "", managementStatus: .connected,
                                    peerInfo: [PeerInfo(ip: "100.64.0.1", fqdn: "box", localIceCandidateEndpoint: "",
                                                      remoteIceCandidateEndpoint: "", localIceCandidateType: "",
                                                      remoteIceCandidateType: "", pubKey: "", latency: "0s",
                                                      bytesRx: 0, bytesTx: 0, connStatus: "Connecting",
                                                      connStatusUpdate: "", direct: false, lastWireguardHandshake: "",
                                                      relayed: false, rosenpassEnabled: false, routes: ["0.0.0.0/0"])])
        stats.ingest(details, connectedSince: nil)
        XCTAssertEqual(stats.box?.connected, false)
    }

    func testNotDirectText() throws {
        try XCTSkipUnless(JetBoxEdition.homeOnly, "английские тексты — сборка США")
        XCTAssertEqual(JBText.route(.notDirect), "Can't reach your JetBox directly")
        XCTAssertEqual(JBText.route(.notDirect, compact: true), "No direct link")
        XCTAssertEqual(JBText.route(.relayed, compact: true), "Relay")
    }

    #if JETBOX_US
    /// Выключатель relay уходит в ядро всегда — и не зависит от настроек.
    func testUSBuildDisablesRelayInCore() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "JetBoxRelayOffTest"))
        defaults.set(true, forKey: GlobalConstants.keyForceRelayConnection)
        defer { defaults.removePersistentDomain(forName: "JetBoxRelayOffTest") }
        let env = try XCTUnwrap(EnvVarPackager.getEnvironmentVariables(defaults: defaults))
        XCTAssertEqual(NetBirdSDKGetEnvKeyNBDisableRelay(), "NB_DISABLE_RELAY")
        XCTAssertEqual(env.get("NB_DISABLE_RELAY"), "true")
        XCTAssertEqual(env.get(NetBirdSDKGetEnvKeyNBForceRelay()), "false")
    }

    func testUSBuildHasNoRelayRoute() {
        XCTAssertEqual(JetBoxLiveStats.route(snapshot(connected: true, relayed: true)), .notDirect)
    }
    #endif
}

/// Сборка 1.0 (20): разрешённый выход для ядра (NB_ALLOWED_EXIT, патч 0004)
/// берётся из записи коробки и доходит до переменной окружения клиента.
final class JetBoxAllowedExitTests: XCTestCase {

    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("allowed-exit-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testFileRoundTripAndChangeDetection() {
        XCTAssertEqual(JetBoxAllowedExit.read(at: tempURL), "", "нет файла — пусто, ни одного выхода")
        XCTAssertTrue(JetBoxAllowedExit.write("sv-demo-us-exit", at: tempURL))
        XCTAssertEqual(JetBoxAllowedExit.read(at: tempURL), "sv-demo-us-exit")
        XCTAssertFalse(JetBoxAllowedExit.write("sv-demo-us-exit", at: tempURL), "то же значение — не изменение")
        XCTAssertTrue(JetBoxAllowedExit.write(nil, at: tempURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path), "без выхода файл убирается")
    }

    #if JETBOX_US
    /// Запись коробки → файл в App Group → переменная NB_ALLOWED_EXIT для ядра.
    func testEnvironmentGetsOwnExitFromBoxRecord() throws {
        let saved = JetBoxStore.currentBox
        let savedFile = JetBoxAllowedExit.read()
        defer {
            JetBoxStore.currentBox = saved
            JetBoxAllowedExit.write(savedFile)
        }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "JetBoxAllowedExitTest"))
        defer { defaults.removePersistentDomain(forName: "JetBoxAllowedExitTest") }

        let savedPeer = JetBoxAllowedPeer.read()
        defer { JetBoxAllowedPeer.write(savedPeer) }
        JetBoxStore.currentBox = JetBoxBox(managementURL: "https://net.jetbox.ai-boss.us",
                                           exitNodeName: "sv-demo-us-exit", selectedExitNode: "sv-demo-us-exit",
                                           boxName: "Demo Home", registeredAt: Date(), boxIP: "100.79.115.162")
        XCTAssertEqual(JetBoxAllowedExit.read(), "sv-demo-us-exit", "файл пишется синхронно с записью коробки")
        XCTAssertEqual(JetBoxAllowedPeer.read(), "100.79.115.162", "адрес пира — тоже синхронно")
        var env = try XCTUnwrap(EnvVarPackager.getEnvironmentVariables(defaults: defaults))
        XCTAssertEqual(NetBirdSDKGetEnvKeyNBAllowedExit(), "NB_ALLOWED_EXIT")
        XCTAssertEqual(NetBirdSDKGetEnvKeyNBAllowedPeerIP(), "NB_ALLOWED_PEER_IP")
        XCTAssertEqual(env.get("NB_ALLOWED_EXIT"), "sv-demo-us-exit")
        XCTAssertEqual(env.get("NB_ALLOWED_PEER_IP"), "100.79.115.162")

        // Запись до 1.0 (21) — без box_ip: ни одного пира (нужен новый вход).
        JetBoxStore.currentBox?.boxIP = nil
        env = try XCTUnwrap(EnvVarPackager.getEnvironmentVariables(defaults: defaults))
        XCTAssertEqual(env.get("NB_ALLOWED_PEER_IP"), "")

        JetBoxStore.currentBox = nil
        env = try XCTUnwrap(EnvVarPackager.getEnvironmentVariables(defaults: defaults))
        XCTAssertEqual(env.get("NB_ALLOWED_EXIT"), "", "нет коробки — ядро не пропустит ни одного выхода")
        XCTAssertEqual(env.get("NB_ALLOWED_PEER_IP"), "", "нет адреса — пустое значение: ядро (jetbox6) снимает привязку к пиру")
    }

    /// verify → ссылка с `b` → полезная нагрузка → запись коробки.
    func testVerifyBoxIPReachesBoxRecord() throws {
        let json = #"{"setup_key":"11111111-2222-4333-8444-555555555555","management_url":"https://net.jetbox.ai-boss.us","exit_node":"sv-demo-us-exit","site_name":"Demo Home","box_ip":"100.79.115.162"}"#
        let url = try XCTUnwrap(JetBoxLoginAPI.connectURL(from: Data(json.utf8)))
        guard case .payload(let payload) = JetBoxLink.parse(url) else { return XCTFail("ссылка не разобралась") }
        XCTAssertEqual(payload.boxIP, "100.79.115.162")
        XCTAssertEqual(payload.exitNodeName, "sv-demo-us-exit")
    }
    #endif

    func testBoxIPValidation() {
        XCTAssertEqual(JetBoxLink.validIP("100.79.115.162"), "100.79.115.162")
        XCTAssertEqual(JetBoxLink.validIP(" 100.79.115.162/32 "), "100.79.115.162", "маску отрезаем")
        XCTAssertNil(JetBoxLink.validIP("100.79.115"))
        XCTAssertNil(JetBoxLink.validIP("box.example"))
        XCTAssertNil(JetBoxLink.validIP(nil))
    }

    #if JETBOX_US
    func testPeerFileRoundTrip() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("peer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(JetBoxAllowedPeer.read(at: url), "")
        XCTAssertTrue(JetBoxAllowedPeer.write("100.79.115.162", at: url))
        XCTAssertEqual(JetBoxAllowedPeer.read(at: url), "100.79.115.162")
        XCTAssertFalse(JetBoxAllowedPeer.write("100.79.115.162", at: url))
    }

    /// В сборке США нет ветки русской редакции: выход — всегда `e` своей коробки.
    func testUSBuildAlwaysPinsOwnExit() {
        XCTAssertTrue(JetBoxEdition.homeOnly)
        let box = JetBoxBox(managementURL: "https://net.jetbox.ai-boss.us", exitNodeName: "sv-demo-us-exit",
                            selectedExitNode: nil, boxName: nil, registeredAt: Date())
        XCTAssertEqual(JetBoxStore.ownExitToAllow(for: box, homeOnly: false), "sv-demo-us-exit",
                       "параметр homeOnly в сборке США ни на что не влияет")
    }
    #endif
}
