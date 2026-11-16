//
//  JetBoxLinkTests.swift
//  NetBirdTests
//
//  Разбор ссылки подключения — по контракту LINK-CONTRACT.md (редакция 1).
//  Ссылка приходит от Кабинета и от старых QR, поэтому проверяем не только
//  счастливый путь, но и мусор: приложение не должно ни падать, ни идти в сеть
//  с кривыми данными.
//

import XCTest
@testable import NetBird

final class JetBoxLinkTests: XCTestCase {

    /// Вымышленная фикстура формата setup-key: настоящих ключей в репозитории
    /// нет и быть не может — низкая энтропия специально, чтобы значение
    /// нельзя было принять за живой ключ.
    private let key = "11111111-2222-4333-8444-555555555555"

    private func parse(_ string: String) -> JetBoxLink.Outcome {
        guard let url = URL(string: string) else {
            XCTFail("URL не разобрался: \(string)")
            return .notOurs
        }
        return JetBoxLink.parse(url)
    }

    private func payload(_ string: String, file: StaticString = #filePath, line: UInt = #line) -> JetBoxLinkPayload? {
        guard case let .payload(p) = parse(string) else {
            XCTFail("ожидали payload, получили \(parse(string))", file: file, line: line)
            return nil
        }
        return p
    }

    // MARK: - Universal Link

    func testUniversalLinkFullContract() {
        let p = payload("https://box.jet-net.net/connect#k=\(key)&m=https%3A%2F%2Fnetbird.jet-net.net&e=box-ivanov-office")
        XCTAssertEqual(p?.setupKey, key)
        XCTAssertEqual(p?.managementURL, "https://netbird.jet-net.net")
        XCTAssertEqual(p?.exitNodeName, "box-ivanov-office")
        XCTAssertNil(p?.boxName)
    }

    func testUniversalLinkWithHumanName() {
        // n=«Офис на Тверской» в percent-encoded UTF-8
        let encoded = "%D0%9E%D1%84%D0%B8%D1%81%20%D0%BD%D0%B0%20%D0%A2%D0%B2%D0%B5%D1%80%D1%81%D0%BA%D0%BE%D0%B9"
        let p = payload("https://box.jet-net.net/connect#k=\(key)&m=https://netbird.jet-net.net&e=box1&n=\(encoded)")
        XCTAssertEqual(p?.boxName, "Офис на Тверской")
        XCTAssertEqual(p?.displayName, "Офис на Тверской")
    }

    func testUniversalLinkTrailingSlashAndSubpath() {
        XCTAssertNotNil(payload("https://box.jet-net.net/connect/#k=\(key)"))
        XCTAssertNotNil(payload("https://box.jet-net.net/connect/ios#k=\(key)"))
    }

    func testHostAndSchemeAreCaseInsensitive() {
        XCTAssertNotNil(payload("HTTPS://BOX.JET-NET.NET/connect#k=\(key)"))
        XCTAssertNotNil(payload("JETBOX://CONNECT#k=\(key)"))
    }

    func testForeignHostIsNotOurs() {
        XCTAssertEqual(parse("https://example.com/connect#k=\(key)"), .notOurs)
        XCTAssertEqual(parse("https://box.jet-net.net.evil.com/connect#k=\(key)"), .notOurs)
    }

    func testForeignPathIsNotOurs() {
        XCTAssertEqual(parse("https://box.jet-net.net/#k=\(key)"), .notOurs)
        XCTAssertEqual(parse("https://box.jet-net.net/connected#k=\(key)"), .notOurs)
    }

    // MARK: - Своя схема

    func testCustomSchemeMatchesUniversalLink() {
        let a = payload("jetbox://connect#k=\(key)&m=https://mgmt.example.net&e=node")
        let b = payload("https://box.jet-net.net/connect#k=\(key)&m=https://mgmt.example.net&e=node")
        XCTAssertEqual(a, b)
    }

    func testForeignSchemeIsNotOurs() {
        XCTAssertEqual(parse("netbird://connect#k=\(key)"), .notOurs)
        XCTAssertEqual(parse("jetbox://disconnect#k=\(key)"), .notOurs)
    }

    // MARK: - Параметры

    func testManagementDefaultsWhenMissingOrEmpty() {
        XCTAssertEqual(payload("jetbox://connect#k=\(key)")?.managementURL,
                       JetBoxConfig.defaultManagementURL)
        XCTAssertEqual(payload("jetbox://connect#k=\(key)&m=")?.managementURL,
                       JetBoxConfig.defaultManagementURL)
    }

    func testManagementNormalisation() {
        XCTAssertEqual(payload("jetbox://connect#k=\(key)&m=https://Mgmt.Example.NET/")?.managementURL,
                       "https://mgmt.example.net")
        XCTAssertEqual(payload("jetbox://connect#k=\(key)&m=https://mgmt.example.net:33073")?.managementURL,
                       "https://mgmt.example.net:33073")
    }

    func testParameterOrderAndUnknownParametersDoNotMatter() {
        let p = payload("jetbox://connect#e=node&z=whatever&m=https://mgmt.example.net&k=\(key)")
        XCTAssertEqual(p?.exitNodeName, "node")
        XCTAssertEqual(p?.managementURL, "https://mgmt.example.net")
    }

    /// Кабинет с 08.09.2026 добавляет в ссылку свой параметр `p=` («что
    /// подключаем»). По контракту §2.1 приложение неизвестные параметры молча
    /// игнорирует: ни разбор, ни удостоверение коробки от `p` не зависят.
    func testCabinetParameterPIsIgnored() {
        let withP = payload("https://box.jet-net.net/connect#k=\(key)&m=https%3A%2F%2Fnetbird.jet-net.net&e=box-ivanov-office&p=%D1%82%D0%B5%D0%BB%D0%B5%D1%84%D0%BE%D0%BD")
        let withoutP = payload("https://box.jet-net.net/connect#k=\(key)&m=https%3A%2F%2Fnetbird.jet-net.net&e=box-ivanov-office")
        XCTAssertEqual(withP, withoutP)
        XCTAssertEqual(withP?.exitNodeName, "box-ivanov-office")
        XCTAssertEqual(withP?.boxIdentity, withoutP?.boxIdentity)
    }

    func testParameterNamesAreCaseInsensitive() {
        XCTAssertEqual(payload("jetbox://connect#K=\(key)&E=node")?.exitNodeName, "node")
    }

    func testExitNodeKeepsCaseAndSpaces() {
        // Сравнение с именем маршрута в ядре точное и регистрозависимое,
        // поэтому разбор не имеет права ничего нормализовать.
        let p = payload("jetbox://connect#k=\(key)&e=Box%20Ivanov")
        XCTAssertEqual(p?.exitNodeName, "Box Ivanov")
        XCTAssertEqual(payload("jetbox://connect#k=\(key)&e=BoxIvanov")?.exitNodeName, "BoxIvanov")
    }

    func testPlusIsNotASpaceInFragment() {
        XCTAssertEqual(payload("jetbox://connect#k=\(key)&e=a+b")?.exitNodeName, "a+b")
    }

    func testEqualsSignInsideValueSurvives() {
        XCTAssertEqual(payload("jetbox://connect#k=\(key)&n=a=b")?.boxName, "a=b")
    }

    // MARK: - Мусор

    func testMissingFragmentIsNotOurs() {
        XCTAssertEqual(parse("https://box.jet-net.net/connect"), .notOurs)
        XCTAssertEqual(parse("https://box.jet-net.net/connect#"), .notOurs)
    }

    func testMissingKeyIsNotOurs() {
        // Без ключа это не ссылка подключения: экраном ошибки не пугаем,
        // для https просто откроется страница /connect.
        XCTAssertEqual(parse("https://box.jet-net.net/connect#m=https://mgmt.example.net"), .notOurs)
        XCTAssertEqual(parse("jetbox://connect#k="), .notOurs)
    }

    func testMalformedKeyIsBroken() {
        XCTAssertEqual(parse("jetbox://connect#k=not-a-uuid"), .broken)
        XCTAssertEqual(parse("jetbox://connect#k=\(key)X"), .broken)
        XCTAssertEqual(parse("jetbox://connect#k=\(key.dropLast())"), .broken)
        // 36 символов, но не UUID
        XCTAssertEqual(parse("jetbox://connect#k=" + String(repeating: "Z", count: 36)), .broken)
    }

    func testNonHttpsManagementIsBroken() {
        XCTAssertEqual(parse("jetbox://connect#k=\(key)&m=http://mgmt.example.net"), .broken)
        XCTAssertEqual(parse("jetbox://connect#k=\(key)&m=mgmt.example.net"), .broken)
        XCTAssertEqual(parse("jetbox://connect#k=\(key)&m=javascript:alert(1)"), .broken)
    }

    func testGarbageFragmentDoesNotCrash() {
        XCTAssertEqual(parse("jetbox://connect#&&&==="), .notOurs)
        XCTAssertEqual(parse("jetbox://connect#k"), .notOurs)
    }

    // MARK: - Показ пользователю

    func testKeyIsNeverShownInFull() {
        let p = payload("jetbox://connect#k=\(key)")
        let masked = p?.maskedKey ?? ""
        XCTAssertFalse(masked.contains(key))
        XCTAssertTrue(masked.hasSuffix(String(key.suffix(4))))
        XCTAssertEqual(masked.filter { $0 == "•" }.count, 8)
    }

    func testDisplayNameFallsBackFromNameToExitToHost() {
        XCTAssertEqual(payload("jetbox://connect#k=\(key)&n=Дом&e=node")?.displayName, "Дом")
        XCTAssertEqual(payload("jetbox://connect#k=\(key)&e=node")?.displayName, "node")
        XCTAssertEqual(payload("jetbox://connect#k=\(key)&m=https://mgmt.example.net")?.displayName,
                       "mgmt.example.net")
    }

    func testBoxIdentityDistinguishesBoxes() {
        let a = payload("jetbox://connect#k=\(key)&m=https://mgmt.example.net&e=one")
        let b = payload("jetbox://connect#k=\(key)&m=https://mgmt.example.net&e=two")
        let sameAsA = payload("jetbox://connect#k=\(key)&m=https://MGMT.example.net/&e=one")
        XCTAssertNotEqual(a?.boxIdentity, b?.boxIdentity)
        XCTAssertEqual(a?.boxIdentity, sameAsA?.boxIdentity)
    }

    // MARK: - Имя дома обновляется по ссылке того же JetBox

    private func stored(_ name: String?) -> JetBoxBox {
        JetBoxBox(managementURL: "https://mgmt.example.net", exitNodeName: "one",
                  selectedExitNode: "one", boxName: name, registeredAt: Date(timeIntervalSince1970: 0))
    }

    func testSameBoxLinkRenamesStoredBox() {
        let link = payload("jetbox://connect#k=\(key)&m=https://mgmt.example.net&e=one&n=%D0%9D%D0%BE%D0%B2%D1%8B%D0%B9")!
        let renamed = stored("Старый").renamed(by: link)
        XCTAssertEqual(renamed?.boxName, "Новый")
        XCTAssertEqual(renamed?.registeredAt, Date(timeIntervalSince1970: 0), "остальное не трогаем")
    }

    func testOtherBoxLinkDoesNotRename() {
        let link = payload("jetbox://connect#k=\(key)&m=https://mgmt.example.net&e=two&n=Other")!
        XCTAssertNil(stored("Старый").renamed(by: link))
    }

    func testLinkWithoutNameOrWithSameNameChangesNothing() {
        XCTAssertNil(stored("Дом").renamed(by: payload("jetbox://connect#k=\(key)&m=https://mgmt.example.net&e=one")!))
        XCTAssertNil(stored("Дом").renamed(by: payload("jetbox://connect#k=\(key)&m=https://mgmt.example.net&e=one&n=%D0%94%D0%BE%D0%BC")!))
    }

    // MARK: - Личность устройства при замене подключения (баг 13.11.2026)

    private let otherKey = "22222222-3333-4444-8555-666666666666"

    private func registered(key: String?, exit: String? = "one", name: String? = "Дом",
                            management: String = "https://mgmt.example.net") -> JetBoxBox {
        JetBoxBox(managementURL: management, exitNodeName: exit, selectedExitNode: exit,
                  boxName: name, registeredAt: Date(timeIntervalSince1970: 0),
                  setupKeyFingerprint: key.map(JetBoxIdentity.fingerprint(of:)))
    }

    func testNoConfigMeansCoreCreatesKeyAnyway() {
        let link = payload("jetbox://connect#k=\(otherKey)&m=https://mgmt.example.net")!
        XCTAssertEqual(JetBoxIdentity.plan(current: registered(key: key), payload: link, configExists: false), .reuse)
        XCTAssertEqual(JetBoxIdentity.plan(current: nil, payload: link, configExists: false), .reuse)
    }

    func testSameLinkReusesIdentity() {
        let link = payload("jetbox://connect#k=\(key)&m=https://mgmt.example.net&e=one")!
        XCTAssertEqual(JetBoxIdentity.plan(current: registered(key: key), payload: link, configExists: true), .reuse)
    }

    func testOtherSetupKeyGetsFreshIdentity() {
        // Облачный абонент: тот же management, другой ключ, выхода в ссылке нет.
        let cloud = payload("jetbox://connect#k=\(otherKey)&m=https://mgmt.example.net&n=Cloud")!
        XCTAssertEqual(JetBoxIdentity.plan(current: registered(key: key), payload: cloud, configExists: true), .fresh)
    }

    func testOtherManagementGetsFreshIdentity() {
        let link = payload("jetbox://connect#k=\(key)&m=https://other.example.net&e=one")!
        XCTAssertEqual(JetBoxIdentity.plan(current: registered(key: key), payload: link, configExists: true), .fresh)
    }

    func testRecordWithoutFingerprintFallsBackToBoxIdentity() {
        // Запись от сборки до 1.0 (9): ровно сценарий бага — коробка, затем облако.
        let cloud = payload("jetbox://connect#k=\(otherKey)&m=https://mgmt.example.net&n=Cloud")!
        let sameBox = payload("jetbox://connect#k=\(otherKey)&m=https://mgmt.example.net&e=one")!
        XCTAssertEqual(JetBoxIdentity.plan(current: registered(key: nil), payload: cloud, configExists: true), .fresh)
        XCTAssertEqual(JetBoxIdentity.plan(current: registered(key: nil), payload: sameBox, configExists: true), .reuse)
    }

    func testForeignConfigGetsFreshIdentity() {
        let link = payload("jetbox://connect#k=\(key)&m=https://mgmt.example.net")!
        XCTAssertEqual(JetBoxIdentity.plan(current: nil, payload: link, configExists: true), .fresh)
    }

    func testFingerprintIsStableAndHidesKey() {
        let fp = JetBoxIdentity.fingerprint(of: key)
        XCTAssertEqual(fp, JetBoxIdentity.fingerprint(of: key.uppercased()), "регистр UUID не важен")
        XCTAssertNotEqual(fp, JetBoxIdentity.fingerprint(of: otherKey))
        XCTAssertEqual(fp.count, 32)
        XCTAssertFalse(fp.contains(String(key.suffix(4))), "в отпечатке нет кусков ключа")
    }

    func testIdentityPrefersExitThenAppTokenThenName() {
        let box = payload("jetbox://connect#k=\(key)&m=https://mgmt.example.net&e=one&t=tok1&n=Dom")!
        let cloudA = payload("jetbox://connect#k=\(key)&m=https://mgmt.example.net&t=tok1&n=Dom")!
        let cloudB = payload("jetbox://connect#k=\(key)&m=https://mgmt.example.net&t=tok2&n=Dom")!
        let legacyA = payload("jetbox://connect#k=\(key)&m=https://mgmt.example.net&n=Dom")!
        let legacyB = payload("jetbox://connect#k=\(key)&m=https://mgmt.example.net&n=Other")!
        XCTAssertEqual(box.boxIdentity, "mgmt.example.net|one", "старый формат удостоверения коробки не меняется")
        XCTAssertNotEqual(cloudA.boxIdentity, cloudB.boxIdentity, "облачных абонентов различает t")
        XCTAssertFalse(cloudA.boxIdentity.contains("tok1"), "токен в удостоверении только отпечатком")
        XCTAssertNotEqual(legacyA.boxIdentity, legacyB.boxIdentity, "без e и t различает n")
    }

    func testStoredBoxMatchesItsOwnCloudLink() {
        let link = payload("jetbox://connect#k=\(key)&m=https://mgmt.example.net&t=tok1&n=Cloud")!
        var box = registered(key: key, exit: nil, name: "Cloud")
        box.appTokenFingerprint = JetBoxIdentity.fingerprint(of: "tok1")
        XCTAssertEqual(box.identity, link.boxIdentity)
        XCTAssertTrue(box.isSameConnection(as: link))
        let other = payload("jetbox://connect#k=\(otherKey)&m=https://mgmt.example.net&t=tok2&n=Cloud")!
        XCTAssertFalse(box.isSameConnection(as: other), "должны спросить «переключить?»")
        XCTAssertNil(box.renamed(by: other), "чужое имя не присваиваем")
    }

    func testReissuedBoxLinkNeedsNoConfirmationButGetsFreshKey() {
        // «Новая ссылка» той же коробки: то же e, другой setup key.
        let current = registered(key: key)
        let reissued = payload("jetbox://connect#k=\(otherKey)&m=https://mgmt.example.net&e=one")!
        XCTAssertTrue(current.isSameConnection(as: reissued))
        XCTAssertEqual(JetBoxIdentity.plan(current: current, payload: reissued, configExists: true), .fresh)
    }

    func testDefaultExitFlag() {
        XCTAssertTrue(payload("jetbox://connect#k=\(key)&e=one")!.enablesDefaultExit)
        XCTAssertFalse(payload("jetbox://connect#k=\(key)&x=0")!.enablesDefaultExit)
        XCTAssertTrue(payload("jetbox://connect#k=\(key)&x=1")!.enablesDefaultExit)
        XCTAssertEqual(payload("jetbox://connect#k=\(key)&t=abc")!.appToken, "abc")
    }

    func testStagedConfigReplacesActiveOnlyOnInstall() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let active = dir.appendingPathComponent("default.json").path
        let staging = JetBoxIdentity.stagingPath(for: active)
        try Data("old".utf8).write(to: URL(fileURLWithPath: active))
        try Data("new".utf8).write(to: URL(fileURLWithPath: staging))

        try JetBoxIdentity.install(staging: staging, into: active)

        XCTAssertEqual(try String(contentsOfFile: active, encoding: .utf8), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging), "временный файл не остаётся")
    }
}
