//
//  GlobalConstantsTests.swift
//  NetBirdTests
//

import XCTest
@testable import NetBird

final class GlobalConstantsTests: XCTestCase {

    func testForceRelayConnectionKey() {
        XCTAssertEqual(GlobalConstants.keyForceRelayConnection, "isConnectionForceRelayed")
    }

    func testLoginRequiredKey() {
        XCTAssertEqual(GlobalConstants.keyLoginRequired, "netbird.loginRequired")
    }

    func testUserPreferencesSuiteName() {
        #if JETBOX_US
        XCTAssertEqual(GlobalConstants.userPreferencesSuiteName, "group.us.aiboss.jetbox")
        #else
        XCTAssertEqual(GlobalConstants.userPreferencesSuiteName, "group.net.jetnet.jetbox")
        #endif
    }

    /// Строки в Swift обязаны совпадать с тем, с чем собрано приложение
    /// (JETBOX_BUNDLE_ID / JETBOX_APP_GROUP в xcconfig): иначе расширение
    /// не найдёт свой профиль, а группа приложений окажется чужой.
    func testIdentifiersMatchTheBuiltApp() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, JetBoxIdentifiers.bundleID)
        XCTAssertEqual(JetBoxIdentifiers.appGroup, "group." + JetBoxIdentifiers.bundleID)
        XCTAssertEqual(NetworkExtensionAdapter().extensionID, JetBoxIdentifiers.bundleID + ".NetworkExtension")
        let appex = Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("NetbirdNetworkExtension.appex")
        if let appex, let ext = Bundle(url: appex) {
            XCTAssertEqual(ext.bundleIdentifier, JetBoxIdentifiers.networkExtension)
        }
    }
}
