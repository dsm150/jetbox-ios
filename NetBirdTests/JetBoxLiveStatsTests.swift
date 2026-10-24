//
//  JetBoxLiveStatsTests.swift
//  NetBirdTests
//
//  Живые показатели нижней панели: какой пир — JetBox, как читается пинг из
//  строки Go и как пишется время в сети.
//

import XCTest
@testable import NetBird

final class JetBoxLiveStatsTests: XCTestCase {

    private func peer(_ name: String, status: String = "Connected", routes: [String] = [],
                      latency: String = "0s", relayed: Bool = false) -> PeerInfo {
        PeerInfo(ip: "100.79.0.1", fqdn: name, localIceCandidateEndpoint: "", remoteIceCandidateEndpoint: "",
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
        XCTAssertEqual(JetBoxHomeProbe.bareIP("100.79.148.91/16"), "100.79.148.91")
        XCTAssertEqual(JetBoxHomeProbe.bareIP("100.79.148.91"), "100.79.148.91")
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
