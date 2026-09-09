//
//  VPNProfileNamingTests.swift
//  NetBirdTests
//
//  Имя VPN-конфигурации в «Настройки → VPN». Форк зовёт профиль «JetBox»,
//  прежние сборки звали «NetBird Network Extension» — и такой профиль уже
//  лежит на телефонах. Цена ошибки в предикате: у клиента появляется второй
//  профиль, а первый остаётся висеть навсегда, поэтому правило под тестами.
//
//  Сам NETunnelProviderManager в юнит-тестах не поднимается (у тестового
//  процесса нет entitlement сетевого расширения) — тестируем предикат.
//

import XCTest
@testable import NetBird

final class VPNProfileNamingTests: XCTestCase {

    private let ourBundleID = "net.jet-net.jetbox.NetworkExtension"
    private let legacyName = "NetBird Network Extension"

    private let naming = VPNProfileNaming(
        name: "JetBox",
        legacyNames: ["NetBird Network Extension"],
        providerBundleIdentifier: "net.jet-net.jetbox.NetworkExtension"
    )

    // MARK: - Свой профиль

    func testCurrentNameIsOursAndNeedsNoRename() {
        XCTAssertTrue(naming.matches(providerBundleIdentifier: ourBundleID, name: "JetBox"))
        XCTAssertFalse(naming.needsRename(providerBundleIdentifier: ourBundleID, name: "JetBox"))
    }

    func testLegacyNameIsStillOursAndNeedsRename() {
        XCTAssertTrue(naming.matches(providerBundleIdentifier: ourBundleID, name: legacyName))
        XCTAssertTrue(naming.needsRename(providerBundleIdentifier: ourBundleID, name: legacyName))
    }

    // MARK: - Чужие профили не трогаем

    func testForeignBundleWithOurNameIsNotOurs() {
        // Так выглядит профиль другой сборки того же приложения: имя может
        // совпасть, удостоверение — нет.
        XCTAssertFalse(naming.matches(providerBundleIdentifier: "io.netbird.app.NetworkExtension",
                                      name: "JetBox"))
        XCTAssertFalse(naming.needsRename(providerBundleIdentifier: "io.netbird.app.NetworkExtension",
                                          name: "JetBox"))
    }

    func testForeignBundleWithLegacyNameIsNotOurs() {
        XCTAssertFalse(naming.matches(providerBundleIdentifier: "io.netbird.app.NetworkExtension",
                                      name: legacyName))
    }

    func testOurBundleWithUnknownNameIsNotOurs() {
        // Профиль, который завёл не мы: bundle ID совпал бы только по ошибке,
        // но имя незнакомое — не переименовываем ничего вслепую.
        XCTAssertFalse(naming.matches(providerBundleIdentifier: ourBundleID, name: "Corporate VPN"))
        XCTAssertFalse(naming.needsRename(providerBundleIdentifier: ourBundleID, name: "Corporate VPN"))
    }

    // MARK: - Пустые значения

    func testMissingBundleIdentifierIsNotOurs() {
        // У профиля с NEVPNProtocolIKEv2 нет providerBundleIdentifier вообще.
        XCTAssertFalse(naming.matches(providerBundleIdentifier: nil, name: "JetBox"))
        XCTAssertFalse(naming.matches(providerBundleIdentifier: nil, name: legacyName))
    }

    func testMissingNameIsNotOurs() {
        XCTAssertFalse(naming.matches(providerBundleIdentifier: ourBundleID, name: nil))
        XCTAssertFalse(naming.needsRename(providerBundleIdentifier: ourBundleID, name: nil))
    }

    // MARK: - Регистр и пробелы значимы

    func testNameComparisonIsExact() {
        // Имя приходит из системных настроек как есть; нормализовать его —
        // значит однажды переименовать чужой профиль.
        XCTAssertFalse(naming.matches(providerBundleIdentifier: ourBundleID, name: "jetbox"))
        XCTAssertFalse(naming.matches(providerBundleIdentifier: ourBundleID, name: " JetBox"))
        XCTAssertFalse(naming.matches(providerBundleIdentifier: ourBundleID, name: "netbird network extension"))
    }

    // MARK: - Настройка адаптера

    func testAdapterUsesJetBoxNameAndKnowsTheLegacyOne() {
        let adapter = NetworkExtensionAdapter()
        XCTAssertEqual(adapter.extensionName, "JetBox")
        XCTAssertEqual(adapter.extensionID, "net.jet-net.jetbox.NetworkExtension")
        XCTAssertTrue(adapter.legacyExtensionNames.contains("NetBird Network Extension"))

        // Профиль, оставшийся от прежней сборки, адаптер обязан узнать
        // и пометить к переименованию — а не завести второй.
        XCTAssertTrue(adapter.profileNaming.needsRename(
            providerBundleIdentifier: adapter.extensionID,
            name: "NetBird Network Extension"))
    }
}
