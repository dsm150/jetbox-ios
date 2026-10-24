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
