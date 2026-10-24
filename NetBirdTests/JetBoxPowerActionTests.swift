//
//  JetBoxPowerActionTests.swift
//  NetBirdTests
//
//  Щит и нижняя кнопка главного экрана зовут одну функцию — проверяем её
//  на всех сочетаниях, чтобы два элемента не могли разойтись.
//

import XCTest
@testable import NetBird

final class JetBoxPowerActionTests: XCTestCase {

    func testDisconnectedWithBoxConnects() {
        XCTAssertEqual(JetBoxPowerAction.action(for: .disconnected, hasBox: true), .connect)
    }

    func testConnectedWithBoxDisconnects() {
        XCTAssertEqual(JetBoxPowerAction.action(for: .connected, hasBox: true), .disconnect)
    }

    func testTransitionsIgnoreTaps() {
        XCTAssertEqual(JetBoxPowerAction.action(for: .connecting, hasBox: true), .none)
        XCTAssertEqual(JetBoxPowerAction.action(for: .disconnecting, hasBox: true), .none)
    }

    func testWithoutBoxNothingHappens() {
        for state in [VPNDisplayState.disconnected, .connecting, .connected, .disconnecting] {
            XCTAssertEqual(JetBoxPowerAction.action(for: state, hasBox: false), .none, "\(state)")
        }
    }

    func testShieldPhaseFollowsTunnel() {
        XCTAssertEqual(JetBoxShieldPhase(state: .disconnected, isInternetConnected: true), .off)
        XCTAssertEqual(JetBoxShieldPhase(state: .connecting, isInternetConnected: true), .working(reverse: false))
        XCTAssertEqual(JetBoxShieldPhase(state: .disconnecting, isInternetConnected: true), .working(reverse: true))
        XCTAssertEqual(JetBoxShieldPhase(state: .connected, isInternetConnected: true), .on)
        XCTAssertEqual(JetBoxShieldPhase(state: .connected, isInternetConnected: false), .offline)
    }
}
