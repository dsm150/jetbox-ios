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
        return JetBoxLink.parse(url, rules: .jetNet)
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
        let a = payload("jetbox://connect#k=\(key)&m=https://mgmt.jet-net.net&e=node")
        let b = payload("https://box.jet-net.net/connect#k=\(key)&m=https://mgmt.jet-net.net&e=node")
        XCTAssertEqual(a, b)
    }

    func testForeignSchemeIsNotOurs() {
        XCTAssertEqual(parse("netbird://connect#k=\(key)"), .notOurs)
        XCTAssertEqual(parse("jetbox://disconnect#k=\(key)"), .notOurs)
    }

    // MARK: - Параметры

    func testManagementDefaultsWhenMissingOrEmpty() {
        XCTAssertEqual(payload("jetbox://connect#k=\(key)")?.managementURL,
                       JetBoxLinkRules.jetNet.defaultManagementURL)
        XCTAssertEqual(payload("jetbox://connect#k=\(key)&m=")?.managementURL,
                       JetBoxLinkRules.jetNet.defaultManagementURL)
    }

    func testManagementNormalisation() {
        XCTAssertEqual(payload("jetbox://connect#k=\(key)&m=https://Mgmt.Jet-Net.NET/")?.managementURL,
                       "https://mgmt.jet-net.net")
        XCTAssertEqual(payload("jetbox://connect#k=\(key)&m=https://mgmt.jet-net.net:33073")?.managementURL,
                       "https://mgmt.jet-net.net:33073")
    }

    func testParameterOrderAndUnknownParametersDoNotMatter() {
        let p = payload("jetbox://connect#e=node&z=whatever&m=https://mgmt.jet-net.net&k=\(key)")
        XCTAssertEqual(p?.exitNodeName, "node")
        XCTAssertEqual(p?.managementURL, "https://mgmt.jet-net.net")
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
        XCTAssertEqual(parse("https://box.jet-net.net/connect#m=https://mgmt.jet-net.net"), .notOurs)
        XCTAssertEqual(parse("jetbox://connect#k="), .notOurs)
    }

    func testMalformedKeyIsBroken() {
        XCTAssertEqual(parse("jetbox://connect#k=not-a-uuid"), .broken)
        XCTAssertEqual(parse("jetbox://connect#k=\(key)X"), .broken)
        XCTAssertEqual(parse("jetbox://connect#k=\(key.dropLast())"), .broken)
        // 36 символов, но не UUID
        XCTAssertEqual(parse("jetbox://connect#k=" + String(repeating: "Z", count: 36)), .broken)
    }

    func testNonHttpsManagementIsForeign() {
        // С ред. 1.3 всё, что не проходит маску, — «не сервер JetBox», а не «ссылка повреждена».
        XCTAssertEqual(parse("jetbox://connect#k=\(key)&m=http://mgmt.jet-net.net"), .foreignServer)
        XCTAssertEqual(parse("jetbox://connect#k=\(key)&m=mgmt.jet-net.net"), .foreignServer)
        XCTAssertEqual(parse("jetbox://connect#k=\(key)&m=javascript:alert(1)"), .foreignServer)
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
        XCTAssertEqual(payload("jetbox://connect#k=\(key)&m=https://mgmt.jet-net.net")?.displayName,
                       "mgmt.jet-net.net")
    }

    func testBoxIdentityDistinguishesBoxes() {
        let a = payload("jetbox://connect#k=\(key)&m=https://mgmt.jet-net.net&e=one")
        let b = payload("jetbox://connect#k=\(key)&m=https://mgmt.jet-net.net&e=two")
        let sameAsA = payload("jetbox://connect#k=\(key)&m=https://MGMT.jet-net.net/&e=one")
        XCTAssertNotEqual(a?.boxIdentity, b?.boxIdentity)
        XCTAssertEqual(a?.boxIdentity, sameAsA?.boxIdentity)
    }

    // MARK: - Имя в удостоверении (контракт 1.3, §2.11)

    private func stored(_ name: String?) -> JetBoxBox {
        JetBoxBox(managementURL: "https://mgmt.jet-net.net", exitNodeName: "one",
                  selectedExitNode: "one", boxName: name, registeredAt: Date(timeIntervalSince1970: 0))
    }

    func testRenamedSiteAsksToSwitch() {
        // Цена правила хост|e|n, принятая руководителем 18.11.2026.
        let link = payload("jetbox://connect#k=\(key)&m=https://mgmt.jet-net.net&e=one&n=%D0%9D%D0%BE%D0%B2%D1%8B%D0%B9")!
        XCTAssertFalse(stored("Старый").isSameConnection(as: link))
        XCTAssertNil(stored("Старый").named(by: link), "переименование — только через подтверждение")
    }

    func testRecordWithoutNameTakesNameFromSameBoxLink() {
        let link = payload("jetbox://connect#k=\(key)&m=https://mgmt.jet-net.net&e=one&n=%D0%94%D0%BE%D0%BC")!
        XCTAssertTrue(stored(nil).isSameConnection(as: link), "запись без n сравниваем без n")
        let named = stored(nil).named(by: link)
        XCTAssertEqual(named?.boxName, "Дом")
        XCTAssertEqual(named?.registeredAt, Date(timeIntervalSince1970: 0), "остальное не трогаем")
    }

    func testLinkWithoutNameMatchesNamedRecord() {
        let link = payload("jetbox://connect#k=\(key)&m=https://mgmt.jet-net.net&e=one")!
        XCTAssertTrue(stored("Дом").isSameConnection(as: link), "старая ссылка без n — та же коробка")
        XCTAssertNil(stored("Дом").named(by: link))
    }

    #if !JETBOX_US
    func testSharedCloudExitNeverMatchesWithoutName() {
        // Общий e облака: запись без имени не считаем «тем же» ни для какой ссылки.
        let cloudNoName = JetBoxBox(managementURL: "https://mgmt.jet-net.net", exitNodeName: "cl-exit",
                                    selectedExitNode: nil, boxName: nil, registeredAt: Date(timeIntervalSince1970: 0))
        let link = payload("jetbox://connect#k=\(key)&m=https://mgmt.jet-net.net&e=cl-exit&n=JetBox%20%C2%B7%20petr")!
        XCTAssertFalse(cloudNoName.isSameConnection(as: link))
        XCTAssertTrue(JetBoxLinkIdentity.isSharedExit("cl-exit"))
        XCTAssertFalse(JetBoxLinkIdentity.isSharedExit("sv-acme-exit"))
    }
    #endif

    func testOtherBoxLinkIsNotSameConnection() {
        let link = payload("jetbox://connect#k=\(key)&m=https://mgmt.jet-net.net&e=two&n=Other")!
        XCTAssertFalse(stored("Старый").isSameConnection(as: link))
        XCTAssertFalse(stored(nil).isSameConnection(as: link))
    }

    /// Общие векторы удостоверения всех платформ (`identity.json`, контракт 1.3, §2.11).
    func testIdentitySharedVectors() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("identity.json")
        struct Vectors: Decodable { struct Case: Decodable { let link: String; let identity: String; let about: String }; let cases: [Case] }
        let vectors = try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
        XCTAssertFalse(vectors.cases.isEmpty)
        for c in vectors.cases {
            XCTAssertEqual(payload(c.link)?.boxIdentity, c.identity, c.about)
        }
    }

    /// Раздел compare общих векторов: запись против ссылки → same / ask.
    func testIdentityCompareSharedVectors() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("identity.json")
        struct Stored: Decodable { let m: String; let e: String?; let n: String? }
        struct Case: Decodable { let stored: Stored; let link: String; let expect: String; let about: String }
        struct Vectors: Decodable { let compare: [Case] }
        let vectors = try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
        XCTAssertFalse(vectors.compare.isEmpty)
        for c in vectors.compare {
            #if JETBOX_US
            // Общий выход облака (cl-…) есть только в русской редакции; в сборке
            // США правила для него нет (1.0 (20)), векторы облака к ней не относятся.
            if c.stored.e?.hasPrefix("cl-") == true { continue }
            #endif
            let box = JetBoxBox(managementURL: c.stored.m, exitNodeName: c.stored.e, selectedExitNode: c.stored.e,
                                boxName: c.stored.n, registeredAt: Date(timeIntervalSince1970: 0))
            let link = try XCTUnwrap(payload(c.link), c.about)
            XCTAssertEqual(box.isSameConnection(as: link) ? "same" : "ask", c.expect, c.about)
        }
    }

    // MARK: - Личность устройства при замене подключения (баг 13.11.2026)

    private let otherKey = "22222222-3333-4444-8555-666666666666"

    private func registered(key: String?, exit: String? = "one", name: String? = "Дом",
                            management: String = "https://mgmt.jet-net.net") -> JetBoxBox {
        JetBoxBox(managementURL: management, exitNodeName: exit, selectedExitNode: exit,
                  boxName: name, registeredAt: Date(timeIntervalSince1970: 0),
                  setupKeyFingerprint: key.map(JetBoxIdentity.fingerprint(of:)))
    }

    func testNoConfigMeansCoreCreatesKeyAnyway() {
        let link = payload("jetbox://connect#k=\(otherKey)&m=https://mgmt.jet-net.net")!
        XCTAssertEqual(JetBoxIdentity.plan(current: registered(key: key), payload: link, configExists: false), .reuse)
        XCTAssertEqual(JetBoxIdentity.plan(current: nil, payload: link, configExists: false), .reuse)
    }

    func testSameLinkReusesIdentity() {
        let link = payload("jetbox://connect#k=\(key)&m=https://mgmt.jet-net.net&e=one")!
        XCTAssertEqual(JetBoxIdentity.plan(current: registered(key: key), payload: link, configExists: true), .reuse)
    }

    func testOtherSetupKeyGetsFreshIdentity() {
        // Облачный абонент: тот же management, другой ключ, выхода в ссылке нет.
        let cloud = payload("jetbox://connect#k=\(otherKey)&m=https://mgmt.jet-net.net&n=Cloud")!
        XCTAssertEqual(JetBoxIdentity.plan(current: registered(key: key), payload: cloud, configExists: true), .fresh)
    }

    func testOtherManagementGetsFreshIdentity() {
        let link = payload("jetbox://connect#k=\(key)&m=https://other.jet-net.net&e=one")!
        XCTAssertEqual(JetBoxIdentity.plan(current: registered(key: key), payload: link, configExists: true), .fresh)
    }

    func testRecordWithoutFingerprintFallsBackToBoxIdentity() {
        // Запись от сборки до 1.0 (9): ровно сценарий бага — коробка, затем облако.
        let cloud = payload("jetbox://connect#k=\(otherKey)&m=https://mgmt.jet-net.net&n=Cloud")!
        let sameBox = payload("jetbox://connect#k=\(otherKey)&m=https://mgmt.jet-net.net&e=one")!
        XCTAssertEqual(JetBoxIdentity.plan(current: registered(key: nil), payload: cloud, configExists: true), .fresh)
        XCTAssertEqual(JetBoxIdentity.plan(current: registered(key: nil), payload: sameBox, configExists: true), .reuse)
    }

    func testForeignConfigGetsFreshIdentity() {
        let link = payload("jetbox://connect#k=\(key)&m=https://mgmt.jet-net.net")!
        XCTAssertEqual(JetBoxIdentity.plan(current: nil, payload: link, configExists: true), .fresh)
    }

    func testFingerprintIsStableAndHidesKey() {
        let fp = JetBoxIdentity.fingerprint(of: key)
        XCTAssertEqual(fp, JetBoxIdentity.fingerprint(of: key.uppercased()), "регистр UUID не важен")
        XCTAssertNotEqual(fp, JetBoxIdentity.fingerprint(of: otherKey))
        XCTAssertEqual(fp.count, 32)
        XCTAssertFalse(fp.contains(String(key.suffix(4))), "в отпечатке нет кусков ключа")
    }

    func testCloudSubscribersAreDistinguishedByName() {
        // Облако: у всех e=cl-exit, различает n; t в удостоверение не входит.
        let mine = payload("jetbox://connect#k=\(key)&m=https://mgmt.jet-net.net&e=cl-exit&n=JetBox%20%C2%B7%20ivan&t=tok1&x=0")!
        let rebind = payload("jetbox://connect#k=\(otherKey)&m=https://mgmt.jet-net.net&e=cl-exit&n=JetBox%20%C2%B7%20ivan&t=tok2&x=0")!
        let other = payload("jetbox://connect#k=\(otherKey)&m=https://mgmt.jet-net.net&e=cl-exit&n=JetBox%20%C2%B7%20petr&t=tok3&x=0")!
        XCTAssertEqual(mine.boxIdentity, rebind.boxIdentity, "«Новая ссылка» своего абонента — без вопроса")
        XCTAssertNotEqual(mine.boxIdentity, other.boxIdentity, "другой абонент — «переключить?»")
        let box = registered(key: key, exit: "cl-exit", name: "JetBox · ivan")
        XCTAssertTrue(box.isSameConnection(as: rebind))
        XCTAssertFalse(box.isSameConnection(as: other))
        XCTAssertEqual(JetBoxIdentity.plan(current: box, payload: rebind, configExists: true), .fresh, "но ключ новый")
    }

    func testReissuedBoxLinkNeedsNoConfirmationButGetsFreshKey() {
        // «Новая ссылка» той же коробки: то же e, другой setup key.
        let current = registered(key: key)
        let reissued = payload("jetbox://connect#k=\(otherKey)&m=https://mgmt.jet-net.net&e=one")!
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

    // MARK: - Маска management *.jet-net.net (контракт 1.3, §2.3)

    /// Общие векторы всех платформ: копия `JetBox_Desktop/core/jetboxlink/testdata/mgmt-mask.json`.
    func testManagementMaskSharedVectors() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("mgmt-mask.json")
        struct Vectors: Decodable { struct Case: Decodable { let m: String; let ok: Bool; let why: String }; let cases: [Case] }
        let vectors = try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(vectors.cases.count, 35)
        for c in vectors.cases {
            XCTAssertEqual(JetBoxLink.allowedManagement(c.m, suffix: JetBoxLinkRules.jetNet.managementSuffix), c.ok, "\(c.m) — \(c.why)")
        }
    }

    func testForeignManagementIsRefusedBeforeAnything() {
        let link = URL(string: "https://box.jet-net.net/connect#k=\(key)&m=https%3A%2F%2Fevil.example.com&e=one")!
        XCTAssertEqual(JetBoxLink.parse(link, rules: .jetNet), .foreignServer)
        let ip = URL(string: "jetbox://connect#k=\(key)&m=https%3A%2F%2F100.64.0.1%3A33073")!
        XCTAssertEqual(JetBoxLink.parse(ip, rules: .jetNet), .foreignServer)
    }

    func testMaskedManagementWithPortIsAccepted() {
        let link = payload("jetbox://connect#k=\(key)&m=https%3A%2F%2Fnetbird.jet-net.net%3A33073&e=one")
        XCTAssertEqual(link?.managementURL, "https://netbird.jet-net.net:33073")
    }

    func testMissingManagementStillMeansDefault() {
        XCTAssertEqual(payload("jetbox://connect#k=\(key)&e=one")?.managementURL, JetBoxLinkRules.jetNet.defaultManagementURL)
    }

    // MARK: - Обрыв сценария замены и завершающая точка (находки Android, 18.11.2026)

    func testInterruptedSwitchRollsBackToPreviousConfig() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let active = dir.appendingPathComponent("default.json").path
        let staging = JetBoxIdentity.stagingPath(for: active)
        try Data("old".utf8).write(to: URL(fileURLWithPath: active))
        try Data("new".utf8).write(to: URL(fileURLWithPath: staging))

        try JetBoxIdentity.install(staging: staging, into: active)
        XCTAssertEqual(try String(contentsOfFile: active, encoding: .utf8), "new")
        JetBoxIdentity.rollback(into: active)

        XCTAssertEqual(try String(contentsOfFile: active, encoding: .utf8), "old", "обрыв — прежний конфиг на месте")
        XCTAssertFalse(FileManager.default.fileExists(atPath: JetBoxIdentity.backupPath(for: active)))
    }

    func testCommittedSwitchDropsBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let active = dir.appendingPathComponent("default.json").path
        let staging = JetBoxIdentity.stagingPath(for: active)
        try Data("old".utf8).write(to: URL(fileURLWithPath: active))
        try Data("new".utf8).write(to: URL(fileURLWithPath: staging))

        try JetBoxIdentity.install(staging: staging, into: active)
        JetBoxIdentity.discardBackup(for: active)
        JetBoxIdentity.rollback(into: active)

        XCTAssertEqual(try String(contentsOfFile: active, encoding: .utf8), "new", "после фиксации откатывать нечего")
    }

    func testTrailingDotIsStrippedFromManagement() {
        let dotted = payload("jetbox://connect#k=\(key)&m=https%3A%2F%2Fnetbird.jet-net.net.&e=one&n=X")
        let plain = payload("jetbox://connect#k=\(key)&m=https%3A%2F%2Fnetbird.jet-net.net&e=one&n=X")
        XCTAssertEqual(dotted?.managementURL, "https://netbird.jet-net.net")
        XCTAssertEqual(dotted?.boxIdentity, plain?.boxIdentity, "тот же сервер — без ложного «Другой JetBox»")
    }
}

// MARK: - Стиль «простое»: выбора выхода нет (замечание Алексея 21.11.2026)

final class JetBoxSimpleStyleExitTests: XCTestCase {

    private let payload = JetBoxLinkPayload(setupKey: "3f6c2a9e-0d41-4c7b-9a55-8e21b07c4d19",
                                            managementURL: "https://mgmt.jet-net.net",
                                            exitNodeName: nil,
                                            boxName: "Дом")

    func testSimpleStyleSkipsExitChoiceLikeNotNow() {
        let step = JetBoxOnboarding.stepForAmbiguousExit(payload: payload, options: ["А", "Б"], style: .simple)
        XCTAssertEqual(step, .protected(exitNode: nil))
    }

    func testSimpleStyleSkipsExitChoiceWhenNoExits() {
        let step = JetBoxOnboarding.stepForAmbiguousExit(payload: payload, options: [], style: .simple)
        XCTAssertEqual(step, .protected(exitNode: nil))
    }

    #if !JETBOX_US
    func testTechnoStyleStillAsksForExit() {
        let step = JetBoxOnboarding.stepForAmbiguousExit(payload: payload, options: ["А", "Б"], style: .techno)
        XCTAssertEqual(step, .chooseExit(payload, options: ["А", "Б"]))
    }
    #endif
}

// MARK: - «Только дом»: выходы скрыты (английская сборка, 21.11.2026)

final class JetBoxHomeOnlyTests: XCTestCase {

    private func payload(x: Bool = true, exit: String? = "cl-exit") -> JetBoxLinkPayload {
        JetBoxLinkPayload(setupKey: "3f6c2a9e-0d41-4c7b-9a55-8e21b07c4d19",
                          managementURL: "https://mgmt.jet-net.net",
                          exitNodeName: exit,
                          boxName: "Home",
                          enablesDefaultExit: x)
    }

    /// 1.0 (14): «только дом» включает выход своей коробки — `e` от Кабинета.
    func testHomeOnlyAppliesOwnBoxExit() {
        XCTAssertTrue(JetBoxEdition.appliesExit(payload: payload(exit: "home-ivanov"), homeOnly: true))
    }

    /// 1.0 (16): в сборке США `x` игнорируется — выход своей коробки включён всегда.
    func testHomeOnlyIgnoresXForOwnExit() {
        XCTAssertTrue(JetBoxEdition.appliesExit(payload: payload(x: false, exit: "home-ivanov"), homeOnly: true))
    }

    func testHomeOnlyNeverAppliesSharedOrMissingExit() {
        #if !JETBOX_US
        XCTAssertFalse(JetBoxEdition.appliesExit(payload: payload(), homeOnly: true), "облако cl-…")
        #endif
        XCTAssertFalse(JetBoxEdition.appliesExit(payload: payload(exit: nil), homeOnly: true), "без e")
        XCTAssertFalse(JetBoxEdition.appliesExit(payload: payload(exit: ""), homeOnly: true))
    }

    func testOwnExitAllowedOnlyForOwnBoxInHomeOnly() {
        let own = JetBoxBox(managementURL: "https://mgmt.jet-net.net", exitNodeName: "home-ivanov",
                            selectedExitNode: nil, boxName: "Home", registeredAt: Date())
        var shared = own; shared.exitNodeName = "cl-exit"
        var none = own; none.exitNodeName = nil
        XCTAssertEqual(JetBoxStore.ownExitToAllow(for: own, homeOnly: true), "home-ivanov", "и без выбора — всегда")
        #if !JETBOX_US
        XCTAssertNil(JetBoxStore.ownExitToAllow(for: own, homeOnly: false), "русская сборка — свой выбор выхода")
        XCTAssertNil(JetBoxStore.ownExitToAllow(for: shared, homeOnly: true))
        #else
        _ = shared
        #endif
        XCTAssertNil(JetBoxStore.ownExitToAllow(for: none, homeOnly: true))
        XCTAssertNil(JetBoxStore.ownExitToAllow(for: nil, homeOnly: true))
    }

    #if !JETBOX_US
    func testWithoutFlagExitFromLinkAppliesAsBefore() {
        XCTAssertTrue(JetBoxEdition.appliesExit(payload: payload(), homeOnly: false))
        XCTAssertFalse(JetBoxEdition.appliesExit(payload: payload(x: false), homeOnly: false))
    }
    #endif

    func testHomeOnlyNeverShowsExitChoiceInEitherStyle() {
        for style in JetBoxStyle.allCases {
            XCTAssertEqual(JetBoxOnboarding.stepForAmbiguousExit(payload: payload(), options: ["A", "B"],
                                                                 style: style, homeOnly: true),
                           .protected(exitNode: nil), "\(style)")
        }
    }

    #if !JETBOX_US
    func testWithoutFlagTechnoStillShowsExitChoice() {
        XCTAssertEqual(JetBoxOnboarding.stepForAmbiguousExit(payload: payload(), options: ["A", "B"],
                                                             style: .techno, homeOnly: false),
                       .chooseExit(payload(), options: ["A", "B"]))
    }
    #endif

    #if !JETBOX_US
    func testFlagParsing() {
        XCTAssertTrue(JetBoxEdition.parse("YES"))
        XCTAssertFalse(JetBoxEdition.parse("NO"))
        XCTAssertFalse(JetBoxEdition.parse(false))
        XCTAssertTrue(JetBoxEdition.parse(nil), "нет ключа — безопасный «только дом»")
        XCTAssertTrue(JetBoxEdition.parse("$(JETBOX_HOME_ONLY)"), "не подставилось — «только дом»")
    }
    #endif

    /// По умолчанию проект собирается как сборка США; русская — явным
    /// `JETBOX_HOME_ONLY=NO`. Проверяем сам проект, а не текущую сборку.
    func testProjectDefaultIsHomeOnly() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NetBird.xcodeproj/project.pbxproj")
        let text = try String(contentsOf: project, encoding: .utf8)
        XCTAssertEqual(text.components(separatedBy: "JETBOX_HOME_ONLY = YES;").count - 1, 2, "Debug и Release проекта")
        XCTAssertFalse(text.contains("JETBOX_HOME_ONLY = NO;"))
    }
}

final class JetBoxHomeOnlyGuardTests: XCTestCase {
    typealias Plan = JetBoxHomeOnlyGuard.Plan

    func testOwnExitIsSelectedWhenNotSelected() {
        XCTAssertEqual(JetBoxHomeOnlyGuard.plan(selectedExit: nil, available: ["home-ivanov"], allowed: "home-ivanov", homeOnly: true),
                       Plan(select: "home-ivanov"))
        XCTAssertEqual(JetBoxHomeOnlyGuard.plan(selectedExit: "other", available: ["other", "home-ivanov"],
                                                allowed: "home-ivanov", homeOnly: true),
                       Plan(select: "home-ivanov"))
    }

    func testOwnExitAlreadySelectedChangesNothing() {
        XCTAssertEqual(JetBoxHomeOnlyGuard.plan(selectedExit: "home-ivanov", available: ["home-ivanov"],
                                                allowed: "home-ivanov", homeOnly: true), Plan())
    }

    /// 1.0 (18): чужие выходы не снимаем — «один в один как русская».
    func testForeignExitIsNotDeselected() {
        XCTAssertEqual(JetBoxHomeOnlyGuard.plan(selectedExit: "cl-exit", available: ["cl-exit"], allowed: nil, homeOnly: true),
                       Plan())
    }

    func testOwnExitMissingFromRoutesSelectsNothing() {
        XCTAssertEqual(JetBoxHomeOnlyGuard.plan(selectedExit: nil, available: ["cl-exit"], allowed: "home-ivanov", homeOnly: true),
                       Plan())
    }

    #if !JETBOX_US
    func testWithoutFlagNothingHappens() {
        XCTAssertEqual(JetBoxHomeOnlyGuard.plan(selectedExit: nil, available: ["home-ivanov"], allowed: "home-ivanov", homeOnly: false),
                       Plan())
    }
    #endif
}

// MARK: - Вход по email (сборка США, схема 22.11.2026)

/// Подменный транспорт: отвечает заданным кодом и телом, запоминает запросы.
private final class JetBoxLoginStub: @unchecked Sendable {
    var replies: [String: (Int, String)] = [:]
    var error: Error?
    /// Сколько первых запросов оборвать (ответ потерян: туннель упал посреди запроса).
    var dropFirst = 0
    private(set) var requests: [URLRequest] = []
    private(set) var logs: [String] = []

    func api() -> JetBoxLoginAPI {
        var api = JetBoxLoginAPI()
        api.transport = { [unowned self] request in
            self.requests.append(request)
            if let error = self.error { throw error }
            if self.dropFirst > 0 { self.dropFirst -= 1; throw URLError(.networkConnectionLost) }
            let path = request.url?.lastPathComponent ?? ""
            let (code, body) = self.replies[path] ?? (500, "")
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
        api.log = { [unowned self] in self.logs.append($0) }
        return api
    }

    func body(_ index: Int) -> [String: String] {
        guard requests.indices.contains(index), let data = requests[index].httpBody,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return json
    }
}

final class JetBoxLoginLinkTests: XCTestCase {
    private let token = "Zq3vX9_kL2-mN8pR4tW6yA0bC5dE7fG1hJ"

    func testVerifyLinkGivesToken() {
        let url = URL(string: "https://jetbox.ai-boss.us/auth/verify#t=\(token)")!
        XCTAssertEqual(JetBoxLoginLink.parse(url), .token(token))
    }

    func testHostAndPathAreCaseInsensitiveAndTrailingSlashOK() {
        let url = URL(string: "https://JetBox.AI-Boss.us/auth/verify/#t=\(token)")!
        XCTAssertEqual(JetBoxLoginLink.parse(url), .token(token))
    }

    func testTokenInQueryIsNotAccepted() {
        // Токен обязан быть во фрагменте: в query он ушёл бы в логи сайта.
        let url = URL(string: "https://jetbox.ai-boss.us/auth/verify?t=\(token)")!
        XCTAssertEqual(JetBoxLoginLink.parse(url), .broken)
    }

    func testOtherHostsAndPathsAreNotOurs() {
        XCTAssertEqual(JetBoxLoginLink.parse(URL(string: "https://evil.example/auth/verify#t=\(token)")!, anyHost: false),
                       .notOurs)
        for raw in ["https://jetbox.ai-boss.us/auth/login#t=\(token)",
                    "https://jetbox.ai-boss.us/#t=\(token)",
                    "http://jetbox.ai-boss.us/auth/verify#t=\(token)",
                    "https://box.jet-net.net/connect#k=11111111-2222-4333-8444-555555555555"] {
            XCTAssertEqual(JetBoxLoginLink.parse(URL(string: raw)!), .notOurs, raw)
        }
    }

    func testDamagedTokenIsBroken() {
        for raw in ["https://jetbox.ai-boss.us/auth/verify",
                    "https://jetbox.ai-boss.us/auth/verify#t=",
                    "https://jetbox.ai-boss.us/auth/verify#t=short",
                    "https://jetbox.ai-boss.us/auth/verify#t=abc%20def%3Cscript%3E1234567890",
                    "https://jetbox.ai-boss.us/auth/verify#x=\(token)"] {
            XCTAssertEqual(JetBoxLoginLink.parse(URL(string: raw)!), .broken, raw)
        }
    }

    func testEmailValidation() {
        XCTAssertTrue(JetBoxEmail.isValid("alex@example.com"))
        XCTAssertTrue(JetBoxEmail.isValid("  a.b+c@mail.co.uk "))
        for bad in ["", "alex", "alex@", "alex@example", "@example.com", "a b@example.com", "alex@example.c"] {
            XCTAssertFalse(JetBoxEmail.isValid(bad), bad)
        }
    }

    func testMailLanguage() {
        XCTAssertEqual(JetBoxLoginAPI.mailLanguage(homeOnly: true, preferred: ["ru-RU"]), "en")
        XCTAssertEqual(JetBoxLoginAPI.mailLanguage(homeOnly: false, preferred: ["ru-RU"]), "ru")
        XCTAssertEqual(JetBoxLoginAPI.mailLanguage(homeOnly: false, preferred: ["en-US"]), "en")
    }
}

final class JetBoxLoginAPITests: XCTestCase {
    private let token = "Zq3vX9_kL2-mN8pR4tW6yA0bC5dE7fG1hJ"
    private let key = "11111111-2222-4333-8444-555555555555"

    private var okBody: String {
        #"{"setup_key":"\#(key)","management_url":"https://\#(JBT.mgmtHost)","exit_node":"home-1","site_name":"Lakeview Home","connect_url":"jetbox://connect#k=\#(key)&m=https%3A%2F%2F\#(JBT.mgmtHost)&e=home-1&n=Lakeview%20Home"}"#
    }

    func testRequestSendsEmailLanguageAndPlatform() async {
        let stub = JetBoxLoginStub()
        stub.replies["request"] = (202, #"{"ok":true}"#)
        let outcome = await stub.api().requestLink(email: " alex@example.com ", language: "en")
        XCTAssertEqual(outcome, .sent)
        XCTAssertEqual(stub.requests.first?.httpMethod, "POST")
        XCTAssertEqual(stub.requests.first?.url?.absoluteString, "\(JBT.api)login/request")
        XCTAssertEqual(stub.body(0), ["email": "alex@example.com", "lang": "en", "platform": "ios"])
    }

    func testRequestOutcomes() async {
        let stub = JetBoxLoginStub()
        stub.replies["request"] = (429, "")
        let limited = await stub.api().requestLink(email: "a@b.co", language: "en")
        XCTAssertEqual(limited, .rateLimited)
        stub.replies["request"] = (503, "")
        let down = await stub.api().requestLink(email: "a@b.co", language: "en")
        XCTAssertEqual(down, .unavailable)
        stub.error = URLError(.notConnectedToInternet)
        let offline = await stub.api().requestLink(email: "a@b.co", language: "en")
        XCTAssertEqual(offline, .offline)
    }

    func testVerifySendsTokenAndDeviceAndReturnsConnectURL() async throws {
        let stub = JetBoxLoginStub()
        stub.replies["verify"] = (200, okBody)
        let outcome = await stub.api().verify(token: token, deviceName: "Alex’s iPhone")
        XCTAssertEqual(stub.requests.first?.url?.absoluteString, "\(JBT.api)login/verify")
        XCTAssertEqual(stub.body(0), ["token": token, "device_name": "Alex’s iPhone", "platform": "ios"])
        guard case .connect(let url) = outcome, case .payload(let payload) = JetBoxLink.parse(url, rules: .current.trustingSource) else {
            return XCTFail("ожидали ссылку подключения, получили \(outcome)")
        }
        XCTAssertEqual(payload.setupKey, key)
        XCTAssertEqual(payload.boxName, "Lakeview Home")
        XCTAssertEqual(payload.exitNodeName, "home-1")
    }

    func testVerifyWithoutConnectURLBuildsLinkFromFields() async {
        let stub = JetBoxLoginStub()
        stub.replies["verify"] = (200, #"{"setup_key":"\#(key)","management_url":"https://\#(JBT.mgmtHost)","site_name":"Дом & сад"}"#)
        let outcome = await stub.api().verify(token: token, deviceName: "iPhone")
        guard case .connect(let url) = outcome, case .payload(let payload) = JetBoxLink.parse(url, rules: .current.trustingSource) else {
            return XCTFail("ожидали ссылку подключения, получили \(outcome)")
        }
        XCTAssertEqual(payload.managementURL, JetBoxConfig.defaultManagementURL)
        XCTAssertEqual(payload.boxName, "Дом & сад")
    }

    func testVerifyResponseWithForeignServerIsNotTrusted() async {
        let stub = JetBoxLoginStub()
        stub.replies["verify"] = (200, #"{"connect_url":"jetbox://connect#k=\#(key)&m=https%3A%2F%2Fevil.example"}"#)
        let outcome = await stub.api().verify(token: token, deviceName: "iPhone")
        #if JETBOX_US
        // США: маски нет (решение владельца 23.11.2026) — сервер из ответа принимается.
        guard case .connect(let url) = outcome, case .payload(let payload) = JetBoxLink.parse(url, rules: .current.trustingSource) else {
            return XCTFail("\(outcome)")
        }
        XCTAssertEqual(payload.managementURL, "https://evil.example")
        #else
        // Русская сборка: ответ проходит маску *.jet-net.net, ключ на чужой сервер не уйдёт.
        XCTAssertEqual(outcome, .unavailable)
        #endif
    }

    func testVerifyOutcomes() async {
        let stub = JetBoxLoginStub()
        let cases: [(Int, String, JetBoxLoginAPI.VerifyOutcome)] = [
            (410, "", .expired),
            (409, #"{"error":"device_limit"}"#, .deviceLimit),
            (409, #"{"error":"not_available"}"#, .notAvailable),
            (409, #"{"error":"other"}"#, .unavailable),
            (429, "", .rateLimited),
            (500, "", .unavailable),
            (200, "not json", .unavailable),
        ]
        for (code, body, expected) in cases {
            stub.replies["verify"] = (code, body)
            let outcome = await stub.api().verify(token: token, deviceName: "iPhone")
            XCTAssertEqual(outcome, expected, "\(code) \(body)")
        }
    }

    func testJournalNeverContainsTokenOrKey() async {
        let stub = JetBoxLoginStub()
        for (code, body) in [(200, okBody), (410, ""), (409, #"{"error":"device_limit"}"#), (429, ""), (500, okBody)] {
            stub.replies["verify"] = (code, body)
            _ = await stub.api().verify(token: token, deviceName: "iPhone")
        }
        stub.replies["request"] = (202, "")
        _ = await stub.api().requestLink(email: "alex@example.com", language: "en")
        XCTAssertFalse(stub.logs.isEmpty)
        for line in stub.logs {
            XCTAssertFalse(line.contains(token), line)
            XCTAssertFalse(line.contains(key), line)
            XCTAssertFalse(line.contains("alex@example.com"), line)
        }
    }
}

@MainActor
final class JetBoxLoginModelTests: XCTestCase {
    func testInvalidEmailDoesNotGoToNetwork() async {
        let stub = JetBoxLoginStub()
        let model = JetBoxLoginModel()
        model.api = stub.api()
        model.email = "alex@"
        await model.submit()
        XCTAssertEqual(model.phase, .enter)
        XCTAssertEqual(model.message, JBText.loginInvalidEmail)
        XCTAssertTrue(stub.requests.isEmpty)
    }

    func testSentThenResendOncePerMinute() async {
        let stub = JetBoxLoginStub()
        stub.replies["request"] = (202, "")
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let model = JetBoxLoginModel()
        model.api = stub.api()
        model.now = { clock }
        model.email = "alex@example.com"
        await model.submit()
        XCTAssertEqual(model.phase, .sent(email: "alex@example.com"))
        XCTAssertEqual(model.resendWait(at: clock), 60)

        clock = clock.addingTimeInterval(30)
        await model.resend()
        XCTAssertEqual(stub.requests.count, 1, "раньше минуты повторно не шлём")
        XCTAssertEqual(model.resendWait(at: clock), 30)

        clock = clock.addingTimeInterval(31)
        await model.resend()
        XCTAssertEqual(stub.requests.count, 2)
        XCTAssertEqual(model.resendWait(at: clock), 60)
        XCTAssertTrue(model.resentNote)
    }

    func testRateLimitShowsClearText() async {
        let stub = JetBoxLoginStub()
        stub.replies["request"] = (429, "")
        let model = JetBoxLoginModel()
        model.api = stub.api()
        model.email = "alex@example.com"
        await model.submit()
        XCTAssertEqual(model.phase, .enter)
        XCTAssertEqual(model.message, JBText.loginRateLimited)
    }
}

@MainActor
final class JetBoxLoginOnboardingTests: XCTestCase {
    private let token = "Zq3vX9_kL2-mN8pR4tW6yA0bC5dE7fG1hJ"
    private let key = "11111111-2222-4333-8444-555555555555"
    private var savedBox: JetBoxBox?

    override func setUp() async throws {
        savedBox = JetBoxStore.currentBox
        JetBoxStore.currentBox = nil
    }

    override func tearDown() async throws {
        JetBoxStore.currentBox = savedBox
    }

    private func settle(_ flow: JetBoxOnboarding) async {
        for _ in 0..<100 where flow.step == .signingIn {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private var link: URL { URL(string: "https://jetbox.ai-boss.us/auth/verify#t=\(token)")! }

    /// Дефект Android (6), проверка для iOS 26: ссылка входа из письма
    /// (https://…/auth/verify#t=…) открывается извне без подписи, а
    /// connect_url из ответа verify — без `s`. Путь «письмо → verify» обязан
    /// пройти как доверенный и в сборке США сразу перейти к подключению,
    /// без «This link isn't from JetBox» и без экрана подтверждения —
    /// и когда ссылка ждала экрана согласия тоже.
    func testEmailLinkVerifyIsTrustedAndConnectsAtOnce() async {
        let connectURL = "jetbox://connect#k=\(key)&m=https%3A%2F%2F\(JBT.mgmtHost)&n=Lakeview%20Home"
        #if JETBOX_US
        XCTAssertEqual(JetBoxLink.parse(URL(string: connectURL)!, rules: .current), .unsigned,
                       "сама по себе такая ссылка была бы отклонена — проходит только как ответ verify")
        #endif
        for heldByConsent in [false, true] {
            let stub = JetBoxLoginStub()
            stub.replies["verify"] = (200, #"{"connect_url":"\#(connectURL)"}"#)
            let flow = JetBoxOnboarding()
            flow.autoConnects = true
            flow.loginAPI = stub.api()
            var consentNeeded = heldByConsent
            flow.needsDataConsent = { consentNeeded }
            XCTAssertTrue(flow.handle(link))
            if heldByConsent {
                XCTAssertEqual(flow.step, .idle, "ссылка ждёт согласия")
                consentNeeded = false
                flow.resumeAfterDataConsent()
            }
            XCTAssertEqual(flow.step, .signingIn)
            await settle(flow)
            XCTAssertNotEqual(flow.step, .failed(.notFromJetBox), "consent=\(heldByConsent)")
            guard case .ready(let payload) = flow.step else { return XCTFail("шаг \(flow.step)") }
            XCTAssertEqual(payload.setupKey, key)
            XCTAssertFalse(flow.isPresenting, "без экрана подтверждения")
            XCTAssertTrue(flow.isConnectingInBackground, "сразу подключение (ждёт только ViewModel)")
            XCTAssertEqual(flow.connectingBox?.displayName, "Lakeview Home")
        }
    }

    func testLoginLinkLeadsToTheConnectScreen() async {
        let stub = JetBoxLoginStub()
        stub.replies["verify"] = (200, #"{"connect_url":"jetbox://connect#k=\#(key)&m=https%3A%2F%2F\#(JBT.mgmtHost)&n=Lakeview%20Home"}"#)
        let flow = JetBoxOnboarding()
        flow.needsDataConsent = { false }
        flow.loginAPI = stub.api()
        XCTAssertTrue(flow.handle(link))
        XCTAssertEqual(flow.step, .signingIn)
        await settle(flow)
        guard case .ready(let payload) = flow.step else { return XCTFail("шаг \(flow.step)") }
        XCTAssertEqual(payload.setupKey, key)
        XCTAssertEqual(payload.boxName, "Lakeview Home")
    }

    func testExpiredLinkAsksForANewOne() async {
        let stub = JetBoxLoginStub()
        stub.replies["verify"] = (410, "")
        let flow = JetBoxOnboarding()
        flow.needsDataConsent = { false }
        flow.loginAPI = stub.api()
        flow.handle(link)
        await settle(flow)
        XCTAssertEqual(flow.step, .failed(.loginExpired))
        XCTAssertTrue(JetBoxFailure.loginExpired.asksForNewLoginLink)
        XCTAssertFalse(JetBoxFailure.loginExpired.isRetryable)
    }

    func testDeviceLimitHasItsOwnText() async {
        let stub = JetBoxLoginStub()
        stub.replies["verify"] = (409, #"{"error":"device_limit"}"#)
        let flow = JetBoxOnboarding()
        flow.needsDataConsent = { false }
        flow.loginAPI = stub.api()
        flow.handle(link)
        await settle(flow)
        XCTAssertEqual(flow.step, .failed(.deviceLimit))
        XCTAssertEqual(JetBoxFailure.deviceLimit.title, JBText.errDeviceLimitTitle)
    }

    /// 1.0 (33): 409 not_available по ссылке из письма — свой отказ, ссылку можно повторить.
    func testNotAvailableHasItsOwnTextAndRetries() async {
        let stub = JetBoxLoginStub()
        stub.replies["verify"] = (409, #"{"error":"not_available"}"#)
        let flow = JetBoxOnboarding()
        flow.needsDataConsent = { false }
        flow.loginAPI = stub.api()
        flow.handle(link)
        await settle(flow)
        XCTAssertEqual(flow.step, .failed(.notAvailable))
        XCTAssertEqual(JetBoxFailure.notAvailable.message, JBText.loginNotAvailable)
        XCTAssertTrue(JetBoxFailure.notAvailable.isRetryable, "Кабинет ссылку не гасит — «Try again»")
    }

    func testDamagedLoginLinkDoesNotGoToNetwork() {
        let stub = JetBoxLoginStub()
        let flow = JetBoxOnboarding()
        flow.needsDataConsent = { false }
        flow.loginAPI = stub.api()
        XCTAssertTrue(flow.handle(URL(string: "https://jetbox.ai-boss.us/auth/verify#t=bad")!))
        XCTAssertEqual(flow.step, .failed(.brokenLink))
        XCTAssertTrue(stub.requests.isEmpty)
    }
}

// MARK: - Код вручную (решение Алексея 22.11.2026)

@MainActor
final class JetBoxLoginCodeTests: XCTestCase {
    private let key = "11111111-2222-4333-8444-555555555555"
    private var connectBody: String {
        #"{"connect_url":"jetbox://connect#k=\#(key)&m=https%3A%2F%2F\#(JBT.mgmtHost)&n=Demo%20Home"}"#
    }

    private func sentModel(_ stub: JetBoxLoginStub, email: String = "alex@example.com") async -> JetBoxLoginModel {
        stub.replies["request"] = (202, "")
        let model = JetBoxLoginModel()
        model.api = stub.api()
        model.deviceName = { "Test iPhone" }
        model.email = email
        await model.submit()
        return model
    }

    func testCodeIsSixDigitsOnly() {
        XCTAssertEqual(JetBoxLoginAPI.normalizedCode(" 123-456 "), "123456")
        XCTAssertEqual(JetBoxLoginAPI.normalizedCode("1234567"), "123456")
        XCTAssertEqual(JetBoxLoginAPI.normalizedCode("12a3"), "123")
        XCTAssertEqual(JetBoxLoginAPI.normalizedCode("١٢٣٤٥٦"), "", "только ASCII-цифры")
    }

    func testApiSendsEmailCodeAndDevice() async {
        let stub = JetBoxLoginStub()
        stub.replies["verify"] = (200, connectBody)
        let outcome = await stub.api().verify(email: " alex@example.com ", code: "123456", deviceName: "Test iPhone")
        XCTAssertEqual(stub.body(0), ["email": "alex@example.com", "code": "123456",
                                      "device_name": "Test iPhone", "platform": "ios"])
        guard case .connect = outcome else { return XCTFail("\(outcome)") }
    }

    func testBadCodeCarriesAttemptsLeft() async {
        let stub = JetBoxLoginStub()
        stub.replies["verify"] = (401, #"{"error":"bad_code","attempts_left":2}"#)
        let left = await stub.api().verify(email: "a@b.co", code: "000000", deviceName: "iPhone")
        XCTAssertEqual(left, .badCode(attemptsLeft: 2))
        stub.replies["verify"] = (401, #"{"error":"bad_code"}"#)
        let unknown = await stub.api().verify(email: "a@b.co", code: "000000", deviceName: "iPhone")
        XCTAssertEqual(unknown, .badCode(attemptsLeft: nil))
        XCTAssertFalse(stub.logs.contains { $0.contains("000000") }, "код в журнал не пишем")
    }

    /// Вход проверяющего Apple: email → «Enter code manually» → постоянный код,
    /// без почты и без ссылки. Подключение получает обычный сценарий.
    func testReviewerPathWorksWithoutMail() async {
        let stub = JetBoxLoginStub()
        let model = await sentModel(stub, email: "appreview@ai-boss.us")
        XCTAssertEqual(model.phase, .sent(email: "appreview@ai-boss.us"))
        model.enterCodeManually()
        XCTAssertEqual(model.phase, .code(email: "appreview@ai-boss.us"))

        var received: URL?
        model.onConnect = { received = $0 }
        stub.replies["verify"] = (200, connectBody)
        model.code = "246 810"
        model.codeChanged()                       // шесть цифр — проверка сама
        for _ in 0..<100 where received == nil { try? await Task.sleep(nanoseconds: 20_000_000) }

        XCTAssertEqual(stub.body(1), ["email": "appreview@ai-boss.us", "code": "246810",
                                      "device_name": "Test iPhone", "platform": "ios"])
        let flow = JetBoxOnboarding()
        flow.needsDataConsent = { false }
        let saved = JetBoxStore.currentBox
        JetBoxStore.currentBox = nil
        defer { JetBoxStore.currentBox = saved }
        XCTAssertTrue(flow.handle(try XCTUnwrap(received), trusted: true))
        guard case .ready(let payload) = flow.step else { return XCTFail("шаг \(flow.step)") }
        XCTAssertEqual(payload.boxName, "Demo Home")
    }

    /// Экран кода (сборка 26): «‹ Back» — к «Check your email», «Use another
    /// email» — сразу к полю email, с чистым кодом и без старой ошибки.
    func testCodeScreenLeadsBackAndToAnotherEmail() async {
        let stub = JetBoxLoginStub()
        let model = await sentModel(stub)
        model.enterCodeManually()
        model.backToLink()
        XCTAssertEqual(model.phase, .sent(email: "alex@example.com"))

        model.enterCodeManually()
        model.code = "12345"
        stub.replies["verify"] = (401, #"{"error":"bad_code","attempts_left":2}"#)
        model.code = "111111"
        await model.submitCode()
        XCTAssertNotNil(model.message)
        model.useAnotherEmail()
        XCTAssertEqual(model.phase, .enter, "одно нажатие — и снова поле email")
        XCTAssertEqual(model.code, "")
        XCTAssertNil(model.message)
    }

    func testWrongAndExpiredCodeMessages() async {
        let stub = JetBoxLoginStub()
        let model = await sentModel(stub)
        model.enterCodeManually()

        stub.replies["verify"] = (401, #"{"error":"bad_code","attempts_left":2}"#)
        model.code = "111111"
        await model.submitCode()
        XCTAssertEqual(model.message, JBText.loginCodeWrongLeft(2))
        XCTAssertEqual(model.code, "", "неверный код стираем — вводить заново")
        XCTAssertEqual(model.phase, .code(email: "alex@example.com"))

        stub.replies["verify"] = (410, "")
        model.code = "222222"
        await model.submitCode()
        XCTAssertEqual(model.message, JBText.loginCodeExpired)

        stub.replies["verify"] = (409, #"{"error":"device_limit"}"#)
        model.code = "333333"
        await model.submitCode()
        XCTAssertEqual(model.message, JBText.errDeviceLimitBody)

        // 1.0 (33): у аккаунта нет живого JetBox — свой текст, а не «не отправили ссылку».
        stub.replies["verify"] = (409, #"{"error":"not_available"}"#)
        model.code = "444444"
        await model.submitCode()
        XCTAssertEqual(model.message, JBText.loginNotAvailable)
        XCTAssertEqual(model.code, "444444", "код верный — стирать незачем")
    }

    func testNewCodeFromCodeScreenStaysOnCodeScreen() async {
        let stub = JetBoxLoginStub()
        var clock = Date(timeIntervalSince1970: 2_000_000)
        stub.replies["request"] = (202, "")
        let model = JetBoxLoginModel()
        model.api = stub.api()
        model.now = { clock }
        model.email = "alex@example.com"
        await model.submit()
        model.enterCodeManually()
        clock = clock.addingTimeInterval(61)
        await model.resend()
        XCTAssertEqual(stub.requests.count, 2)
        XCTAssertEqual(model.phase, .code(email: "alex@example.com"))
    }

    func testShortCodeIsNotSent() async {
        let stub = JetBoxLoginStub()
        let model = await sentModel(stub)
        model.enterCodeManually()
        model.code = "12345"
        await model.submitCode()
        XCTAssertEqual(stub.requests.count, 1, "только запрос письма")
    }
}

/// «Sign out» (1.0 (13)): туннель выключен, профиль стёрт, записи JetBox нет —
/// экран входа по email снова на месте, и вход по коду работает заново.
@MainActor
final class JetBoxSignOutTests: XCTestCase {
    private let key = "11111111-2222-4333-8444-555555555555"
    private var savedBox: JetBoxBox?
    private var dir: URL!

    override func setUp() async throws {
        savedBox = JetBoxStore.currentBox
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jetbox-signout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        JetBoxStore.currentBox = savedBox
        try? FileManager.default.removeItem(at: dir)
    }

    private var files: JetBoxSignOut.Files {
        JetBoxSignOut.Files(configPath: dir.appendingPathComponent("netbird.cfg").path,
                            statePath: dir.appendingPathComponent("state.json").path,
                            profileID: "default")
    }

    private func box(_ name: String) -> JetBoxBox {
        JetBoxBox(managementURL: "https://netbird.jet-net.net", exitNodeName: nil, selectedExitNode: nil,
                  boxName: name, registeredAt: Date(), setupKeyFingerprint: JetBoxIdentity.fingerprint(of: key))
    }

    func testWipesTheSameFilesAsRemoveProfile() {
        let names = Set(files.paths.map { URL(fileURLWithPath: $0).lastPathComponent })
        XCTAssertEqual(names, ["netbird.cfg", "netbird.cfg.jetbox-new", "netbird.cfg.jetbox-old",
                               "netbird.account.json", "default.prefs.json", "state.json"])
    }

    func testSignOutStopsTunnelWipesProfileAndShowsEmailLogin() async {
        let fm = FileManager.default
        for path in files.paths { fm.createFile(atPath: path, contents: Data("{}".utf8)) }
        let foreign = dir.appendingPathComponent("keep.json").path
        fm.createFile(atPath: foreign, contents: Data())
        JetBoxStore.currentBox = box("Lakeview Home")
        XCTAssertFalse(JetBoxEdition.showsEmailLogin(homeOnly: true, box: JetBoxStore.currentBox))

        let flow = JetBoxOnboarding()

        flow.needsDataConsent = { false }
        var stopped = false
        await flow.signOut(stopTunnel: { stopped = true }, files: files)

        XCTAssertTrue(stopped, "туннель выключаем до стирания")
        XCTAssertNil(JetBoxStore.currentBox)
        XCTAssertTrue(JetBoxEdition.showsEmailLogin(homeOnly: true, box: JetBoxStore.currentBox))
        XCTAssertEqual(flow.step, .idle)
        XCTAssertEqual(flow.signOutCount, 1)
        for path in files.paths { XCTAssertFalse(fm.fileExists(atPath: path), path) }
        XCTAssertTrue(fm.fileExists(atPath: foreign), "чужие файлы не трогаем")
    }

    func testCodeLoginWorksAgainAfterSignOut() async throws {
        JetBoxStore.currentBox = box("Old Home")
        let flow = JetBoxOnboarding()
        flow.needsDataConsent = { false }
        await flow.signOut(stopTunnel: {}, files: files)

        let stub = JetBoxLoginStub()
        stub.replies["request"] = (202, "")
        let model = JetBoxLoginModel()
        model.api = stub.api()
        model.deviceName = { "Test iPhone" }
        model.email = "old@example.com"
        await model.submit()
        model.enterCodeManually()
        model.reset()                                  // главный экран после выхода
        XCTAssertEqual(model.phase, .enter)
        XCTAssertEqual(model.email, "")
        XCTAssertNil(model.lastSentAt)

        model.email = "appreview@ai-boss.us"
        await model.submit()
        model.enterCodeManually()
        var received: URL?
        model.onConnect = { received = $0 }
        stub.replies["verify"] = (200, #"{"connect_url":"jetbox://connect#k=\#(key)&m=https%3A%2F%2F\#(JBT.mgmtHost)&n=Demo%20Home"}"#)
        model.code = "246810"
        await model.submitCode()

        XCTAssertTrue(flow.handle(try XCTUnwrap(received), trusted: true))
        // Записи нет — без «переключить?», сразу одна кнопка, как после установки.
        guard case .ready(let payload) = flow.step else { return XCTFail("шаг \(flow.step)") }
        XCTAssertEqual(payload.boxName, "Demo Home")
    }
}

/// Вход в сборке США (1.0 (16)): выход своей коробки включён всегда, `x`
/// игнорируется, тумблера нет. Тестовое приложение собрано с JETBOX_HOME_ONLY=YES.
final class JetBoxOwnExitRememberTests: XCTestCase {
    private var savedBox: JetBoxBox?

    override func setUp() {
        savedBox = JetBoxStore.currentBox
    }

    override func tearDown() {
        JetBoxStore.currentBox = savedBox
    }

    private func payload(x: Bool, exit: String?) -> JetBoxLinkPayload {
        JetBoxLinkPayload(setupKey: "3f6c2a9e-0d41-4c7b-9a55-8e21b07c4d19",
                          managementURL: "https://mgmt.jet-net.net", exitNodeName: exit,
                          boxName: "Lakeview Home", enablesDefaultExit: x)
    }

    func testLoginTurnsOwnExitOn() throws {
        try XCTSkipUnless(JetBoxEdition.homeOnly, "проверка сборки США")
        JetBoxStore.remember(payload(x: true, exit: "home-ivanov"))
        XCTAssertEqual(JetBoxStore.currentBox?.selectedExitNode, "home-ivanov")
        XCTAssertTrue(JetBoxStore.allInternetHome)
    }

    func testXZeroIsIgnored() throws {
        try XCTSkipUnless(JetBoxEdition.homeOnly, "проверка сборки США")
        JetBoxStore.remember(payload(x: false, exit: "home-ivanov"))
        XCTAssertEqual(JetBoxStore.currentBox?.selectedExitNode, "home-ivanov")
        XCTAssertTrue(JetBoxStore.allInternetHome)
    }

    #if !JETBOX_US
    func testCloudExitNeverTurnsOn() throws {
        try XCTSkipUnless(JetBoxEdition.homeOnly, "проверка сборки США")
        JetBoxStore.remember(payload(x: true, exit: "cl-exit"))
        XCTAssertNil(JetBoxStore.currentBox?.selectedExitNode)
        XCTAssertFalse(JetBoxStore.allInternetHome)
    }
    #endif

    /// Записи 12–15: выход мог быть не выбран (x=0 или тумблер) — при запуске выбираем.
    func testOldRecordGetsOwnExitSelected() throws {
        try XCTSkipUnless(JetBoxEdition.homeOnly, "проверка сборки США")
        JetBoxStore.currentBox = JetBoxBox(managementURL: "https://mgmt.jet-net.net", exitNodeName: "home-ivanov",
                                           selectedExitNode: nil, boxName: "Home", registeredAt: Date())
        JetBoxStore.selectOwnExitIfNeeded()
        XCTAssertEqual(JetBoxStore.currentBox?.selectedExitNode, "home-ivanov")
    }

    /// Баг 1.0 (16): «Protected» горел при трафике мимо дома. Теперь — только
    /// когда маршрут по умолчанию стоит в применённых настройках туннеля.
    func testProtectedOnlyWhenDefaultRouteIsInTunnel() {
        XCTAssertTrue(JBText.allInternetHome(expected: true, inTunnel: true))
        XCTAssertFalse(JBText.allInternetHome(expected: true, inTunnel: false), "выход выбран, а маршрута нет")
        XCTAssertFalse(JBText.allInternetHome(expected: false, inTunnel: true), "нет выхода своей коробки")
    }

    func testWarningWhenExpectedExitIsNotInTunnel() throws {
        try XCTSkipUnless(JetBoxEdition.homeOnly, "английские тексты — сборка США")
        XCTAssertEqual(JBText.exitWarning(expected: true, inTunnel: false),
                       "Internet isn’t going through your JetBox right now.")
        XCTAssertNil(JBText.exitWarning(expected: true, inTunnel: true))
        XCTAssertNil(JBText.exitWarning(expected: false, inTunnel: false), "без `e` — просто «On your home network»")
    }

    func testStatusTextsWithoutExit() throws {
        try XCTSkipUnless(JetBoxEdition.homeOnly, "проверка сборки США")
        JetBoxStore.remember(payload(x: true, exit: nil))
        XCTAssertEqual(JBText.homeConnectedNow, "On your home network")
        XCTAssertEqual(JBText.dockOnNow, "On your home network")
        XCTAssertEqual(JBText.protectedTitle(exitNode: nil), "On your home network")
    }
}

/// Маршрут по умолчанию в туннеле: что ставит расширение и что видит приложение.
final class JetBoxTunnelDefaultRouteTests: XCTestCase {
    private var file: URL!

    override func setUp() {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("jetbox-tunnel-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: file)
    }

    func testStateRoundTripAndFreshRead() {
        XCTAssertFalse(JetBoxTunnelState.defaultRouteInTunnel(at: file), "нет файла — маршрута нет")
        JetBoxTunnelState.write(defaultRouteInTunnel: true, at: file)
        XCTAssertTrue(JetBoxTunnelState.defaultRouteInTunnel(at: file))
        JetBoxTunnelState.write(defaultRouteInTunnel: false, at: file)
        XCTAssertFalse(JetBoxTunnelState.defaultRouteInTunnel(at: file))
    }

    func testReadinessWaitsForDefaultRouteOnlyWhenExitExpected() {
        XCTAssertFalse(JetBoxHomeReadiness.exitReady(expected: true, inTunnel: false))
        XCTAssertTrue(JetBoxHomeReadiness.exitReady(expected: true, inTunnel: true))
        XCTAssertTrue(JetBoxHomeReadiness.exitReady(expected: false, inTunnel: false))
    }
}

// MARK: - «Delete account» (Apple 5.1.1(v), 1.0 (14))

@MainActor
final class JetBoxAccountDeleteTests: XCTestCase {
    private let key = "11111111-2222-4333-8444-555555555555"
    private var savedBox: JetBoxBox?
    private var token: String?
    private var tokenDeleted = 0

    private let deleteDefaults = UserDefaults(suiteName: "jetbox-delete-tests")!

    override func setUp() async throws {
        savedBox = JetBoxStore.currentBox
        token = nil
        tokenDeleted = 0
        deleteDefaults.removePersistentDomain(forName: "jetbox-delete-tests")
    }

    override func tearDown() async throws {
        JetBoxStore.currentBox = savedBox
    }

    private func flow(_ stub: JetBoxLoginStub) -> JetBoxOnboarding {
        let flow = JetBoxOnboarding()
        flow.needsDataConsent = { false }
        flow.loginAPI = stub.api()
        flow.loadAppToken = { [unowned self] in self.token }
        flow.deleteAppToken = { [unowned self] in self.token = nil; self.tokenDeleted += 1 }
        flow.deleteDefaults = deleteDefaults
        flow.deleteRetryDelay = 0
        JetBoxStore.currentBox = JetBoxBox(managementURL: "https://netbird.jet-net.net", exitNodeName: "home-ivanov",
                                           selectedExitNode: "home-ivanov", boxName: "Lakeview Home", registeredAt: Date())
        return flow
    }

    func testDeleteSendsBearerTokenAndSignsOutOn200() async {
        let stub = JetBoxLoginStub()
        stub.replies["delete"] = (200, #"{"ok":true}"#)
        let flow = flow(stub)
        token = "app-token-123"
        var stopped = false
        let result = await flow.deleteAccount(stopTunnel: { stopped = true }, files: nil)

        XCTAssertEqual(result, .deleted)
        XCTAssertEqual(stub.requests.first?.url?.absoluteString, "\(JBT.api)account/delete")
        XCTAssertEqual(stub.requests.first?.httpMethod, "POST")
        XCTAssertEqual(stub.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer app-token-123")
        XCTAssertTrue(stopped)
        XCTAssertNil(JetBoxStore.currentBox, "дальше — экран email")
        XCTAssertEqual(flow.signOutCount, 1)
        XCTAssertNil(token, "токен стёрт вместе с профилем")
        XCTAssertEqual(flow.takeLoginNotice(), JBText.deleteDone, "экран входа говорит «Account deleted»")
        XCTAssertFalse(stub.logs.joined().contains("app-token-123"), "токен в журнал не пишем")
    }

    func testRevokedToken401AlsoSignsOut() async {
        let stub = JetBoxLoginStub()
        stub.replies["delete"] = (401, #"{"error":"unauthorized"}"#)
        let flow = flow(stub)
        token = "old"
        let result = await flow.deleteAccount(stopTunnel: {}, files: nil)
        XCTAssertEqual(result, .deleted)
        XCTAssertNil(JetBoxStore.currentBox)
        XCTAssertEqual(flow.takeLoginNotice(), JBText.deleteSignInAgain,
                       "401 без отправленного удаления — токен погашен раньше")
    }

    /// 1.0 (32): Кабинет снял доступ, туннель упал, ответ потерян — автоматический
    /// повтор получает 401, и это успех, а не «токен погашен».
    func testLostAnswerThenRetry401IsSuccess() async {
        let stub = JetBoxLoginStub()
        stub.dropFirst = 1
        stub.replies["delete"] = (401, #"{"error":"unauthorized"}"#)
        let flow = flow(stub)
        token = "app-token"
        var requestsWhenStopped: Int?
        let result = await flow.deleteAccount(stopTunnel: {
            if requestsWhenStopped == nil { requestsWhenStopped = stub.requests.count }
        }, files: nil)
        XCTAssertEqual(result, .deleted)
        XCTAssertEqual(stub.requests.count, 2, "один автоматический повтор")
        XCTAssertEqual(requestsWhenStopped, 1, "1.0 (34): туннель выключен до повтора — повтор идёт напрямую")
        XCTAssertNil(JetBoxStore.currentBox)
        XCTAssertEqual(flow.takeLoginNotice(), JBText.deleteDone)
    }

    /// Повтор руками после неудачи с обрывом: 401 — тоже успех.
    func testManualRetryAfterLostAnswerIsSuccess() async {
        let stub = JetBoxLoginStub()
        stub.dropFirst = 2
        let flow = flow(stub)
        token = "app-token"
        let first = await flow.deleteAccount(stopTunnel: {}, files: nil)
        XCTAssertEqual(first, .failed, "оба запроса оборваны — «попробуйте ещё раз»")
        XCTAssertNotNil(JetBoxStore.currentBox)
        stub.replies["delete"] = (401, "")
        let second = await flow.deleteAccount(stopTunnel: {}, files: nil)
        XCTAssertEqual(second, .deleted)
        XCTAssertEqual(flow.takeLoginNotice(), JBText.deleteDone)
    }

    /// 1.0 (32): единственный владелец — 409 last_owner, ничего не стираем.
    func testLastOwnerKeepsEverythingAndNamesSupport() async {
        for (body, expected) in [(#"{"error":"last_owner","support":"help@example.com"}"#, "help@example.com"),
                                 (#"{"error":"last_owner","support":""}"#, JetBoxOnboarding.defaultSupportEmail)] {
            let stub = JetBoxLoginStub()
            stub.replies["delete"] = (409, body)
            let flow = flow(stub)
            token = "app-token"
            var stopped = false
            let result = await flow.deleteAccount(stopTunnel: { stopped = true }, files: nil)
            XCTAssertEqual(result, .lastOwner(support: expected))
            XCTAssertFalse(stopped)
            XCTAssertNotNil(JetBoxStore.currentBox)
            XCTAssertEqual(token, "app-token")
            XCTAssertEqual(flow.signOutCount, 0)
        }
        XCTAssertEqual(JetBoxOnboarding.defaultSupportEmail, "dev@ai-boss.us")
    }

    /// Другой 409 — общая ошибка.
    func testOther409IsGenericFailure() async {
        let stub = JetBoxLoginStub()
        stub.replies["delete"] = (409, #"{"error":"busy"}"#)
        let flow = flow(stub)
        token = "app-token"
        let result = await flow.deleteAccount(stopTunnel: {}, files: nil)
        XCTAssertEqual(result, .failed)
    }

    func testServerErrorKeepsEverything() async {
        for code in [500, 502, 429] {
            let stub = JetBoxLoginStub()
            stub.replies["delete"] = (code, "")
            let flow = flow(stub)
            token = "app-token"
            var stopped = false
            let result = await flow.deleteAccount(stopTunnel: { stopped = true }, files: nil)
            XCTAssertEqual(result, .failed, "\(code)")
            XCTAssertFalse(stopped, "\(code): туннель не трогаем")
            XCTAssertNotNil(JetBoxStore.currentBox, "\(code): ничего не стираем")
            XCTAssertEqual(token, "app-token")
            XCTAssertEqual(flow.signOutCount, 0)
        }
    }

    func testOfflineKeepsEverything() async {
        let stub = JetBoxLoginStub()
        stub.error = URLError(.notConnectedToInternet)
        let flow = flow(stub)
        token = "app-token"
        let result = await flow.deleteAccount(stopTunnel: {}, files: nil)
        XCTAssertEqual(result, .failed)
        XCTAssertNotNil(JetBoxStore.currentBox)
    }

    func testWithoutTokenSignsOutLocallyAndAsksToSignInAgain() async {
        let stub = JetBoxLoginStub()
        let flow = flow(stub)
        let result = await flow.deleteAccount(stopTunnel: {}, files: nil)
        XCTAssertEqual(result, .signInAgain)
        XCTAssertTrue(stub.requests.isEmpty, "без токена в Кабинет не ходим")
        XCTAssertNil(JetBoxStore.currentBox)
        XCTAssertEqual(flow.takeLoginNotice(), JBText.deleteSignInAgain)
        XCTAssertNil(flow.takeLoginNotice(), "сообщение показываем один раз")
    }

    func testSignOutWipesAppToken() async {
        let stub = JetBoxLoginStub()
        let flow = flow(stub)
        token = "app-token"
        await flow.signOut(stopTunnel: {}, files: nil)
        XCTAssertNil(token)
        XCTAssertEqual(tokenDeleted, 1)
    }

    func testVerifyStoresAppTokenButNotInLink() async {
        let stub = JetBoxLoginStub()
        stub.replies["verify"] = (200, #"{"connect_url":"jetbox://connect#k=\#(key)&n=Demo%20Home","app_token":"tok-1"}"#)
        var api = stub.api()
        var stored: [String?] = []
        api.storeAppToken = { stored.append($0) }
        let outcome = await api.verify(email: "a@b.co", code: "123456", deviceName: "iPhone")
        guard case .connect(let url) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(stored, ["tok-1"])
        XCTAssertFalse(url.absoluteString.contains("tok-1"))
        XCTAssertFalse(stub.logs.joined().contains("tok-1"))
    }

    func testVerifyWithoutTokenClearsOldOne() async {
        let stub = JetBoxLoginStub()
        stub.replies["verify"] = (200, #"{"connect_url":"jetbox://connect#k=\#(key)&n=Demo%20Home"}"#)
        var api = stub.api()
        var stored: [String?] = ["old"]
        api.storeAppToken = { stored.append($0) }
        _ = await api.verify(email: "a@b.co", code: "123456", deviceName: "iPhone")
        XCTAssertEqual(stored, ["old", nil])
    }

    func testKeychainRoundTrip() {
        let service = JetBoxAppToken.service + ".tests"
        JetBoxAppToken.delete(service: service)
        XCTAssertNil(JetBoxAppToken.load(service: service))
        XCTAssertTrue(JetBoxAppToken.save("tok-A", service: service))
        XCTAssertTrue(JetBoxAppToken.save("tok-B", service: service), "перезапись")
        XCTAssertEqual(JetBoxAppToken.load(service: service), "tok-B")
        JetBoxAppToken.delete(service: service)
        XCTAssertNil(JetBoxAppToken.load(service: service))
    }

    func testLoginNoticeShowsOnCleanEmailScreen() throws {
        try XCTSkipUnless(JetBoxEdition.homeOnly, "английские тексты — сборка США")
        let model = JetBoxLoginModel()
        model.reset()
        model.showNotice(JBText.deleteSignInAgain)
        XCTAssertEqual(model.notice, "Log in again to finish deleting your account.")
        XCTAssertNil(model.message, "сообщение после удаления — не ошибка")
        XCTAssertEqual(model.phase, .enter)
    }
}

// MARK: - «Подключено» — когда отвечает дом (1.0 (14))

final class JetBoxHomeReadinessTests: XCTestCase {
    private func peer(_ name: String, status: String = "Connected", routes: [String] = []) -> PeerInfo {
        PeerInfo(ip: "100.64.0.9/16", fqdn: name, localIceCandidateEndpoint: "", remoteIceCandidateEndpoint: "",
                 localIceCandidateType: "", remoteIceCandidateType: "", pubKey: "", latency: "0s",
                 bytesRx: 0, bytesTx: 0, connStatus: status, connStatusUpdate: "", direct: true,
                 lastWireguardHandshake: "", relayed: false, rosenpassEnabled: false, routes: routes)
    }

    func testConnectedTunnelShowsConnectingUntilHomeAnswers() {
        XCTAssertEqual(JetBoxHomeReadiness.displayState(.connected, homeReady: false), .connecting)
        XCTAssertEqual(JetBoxHomeReadiness.displayState(.connected, homeReady: true), .connected)
        XCTAssertEqual(JetBoxHomeReadiness.displayState(.disconnected, homeReady: false), .disconnected)
        XCTAssertEqual(JetBoxHomeReadiness.displayState(.disconnecting, homeReady: true), .disconnecting)
    }

    func testHomePeerIsTheExitPeer() {
        let peers = [peer("laptop"), peer("box", status: "Connecting", routes: ["192.168.60.0/24", "0.0.0.0/0"])]
        let home = JetBoxHomeReadiness.homePeer(in: peers)
        XCTAssertEqual(home?.fqdn, "box")
        XCTAssertFalse(JetBoxHomeReadiness.isConnected(home!), "пир коробки ещё не поднялся — ждём")
    }

    func testHomePeerWithoutExitIsThePeerWithHomeRoutes() {
        // Выход выключен тумблером: коробку узнаём по сети дома.
        let peers = [peer("laptop"), peer("box", routes: ["192.168.60.0/24"])]
        XCTAssertEqual(JetBoxHomeReadiness.homePeer(in: peers)?.fqdn, "box")
    }

    func testNoHomePeerYet() {
        XCTAssertNil(JetBoxHomeReadiness.homePeer(in: [peer("laptop")]))
        XCTAssertNil(JetBoxHomeReadiness.homePeer(in: []))
    }

    func testCeilingIs90Seconds() {
        XCTAssertEqual(JetBoxHomeReadiness.timeout, 90)
    }
}

// MARK: - Бэкап на новый телефон (1.0 (14))

final class JetBoxBackupTests: XCTestCase {
    private let box = JetBoxBox(managementURL: "https://netbird.jet-net.net", exitNodeName: nil, selectedExitNode: nil,
                                boxName: "Home", registeredAt: Date())

    func testRecordWithoutConfigIsOrphaned() {
        XCTAssertTrue(JetBoxBackup.isOrphaned(box: box, configPath: "/x/netbird.cfg", fileExists: { _ in false }))
    }

    func testRecordWithConfigStays() {
        XCTAssertFalse(JetBoxBackup.isOrphaned(box: box, configPath: "/x/netbird.cfg", fileExists: { _ in true }))
    }

    func testUnknownConfigPathNeverDropsRecord() {
        XCTAssertFalse(JetBoxBackup.isOrphaned(box: box, configPath: nil, fileExists: { _ in false }))
        XCTAssertFalse(JetBoxBackup.isOrphaned(box: nil, configPath: "/x/netbird.cfg", fileExists: { _ in false }))
    }
}

extension JetBoxLinkRules {
    /// Правила русской сборки: на них написаны общие векторы всех платформ
    /// (`identity.json`, `mgmt-mask.json`) — разбор от редакции не зависит.
    static let jetNet = JetBoxLinkRules(connectHost: "box.jet-net.net",
                                        managementSuffix: ".jet-net.net",
                                        defaultManagementURL: "https://netbird.jet-net.net")
}

/// Адреса редакции, под которую собраны тесты: сценарии входа идут через код
/// приложения, а он берёт хосты из Info.plist (Config/JetBoxEdition.xcconfig).
enum JBT {
    static var mgmtHost: String { URL(string: JetBoxConfig.defaultManagementURL)?.host ?? "" }
    static var api: String { JetBoxConfig.loginAPIBase.absoluteString }
}

/// Сборка 1.0 (18): согласие «какие данные собираем» до входа и подключения.
@MainActor
final class JetBoxDataConsentTests: XCTestCase {
    private let key = "11111111-2222-4333-8444-555555555555"
    private let token = "tok_abcdefghijklmnopqrstuvwxyz012345"

    func testConsentIsAskedOnlyInUSBuildAndOnlyOnce() {
        XCTAssertTrue(JetBoxDataConsent.needsConsent(homeOnly: true, accepted: false))
        XCTAssertFalse(JetBoxDataConsent.needsConsent(homeOnly: true, accepted: true))
        XCTAssertFalse(JetBoxDataConsent.needsConsent(homeOnly: false, accepted: false))
    }

    func testAcceptIsRemembered() {
        let defaults = UserDefaults(suiteName: "JetBoxDataConsentTests")!
        defaults.removePersistentDomain(forName: "JetBoxDataConsentTests")
        XCTAssertFalse(defaults.bool(forKey: JetBoxDataConsent.acceptedKey))
        JetBoxDataConsent.accept(defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: JetBoxDataConsent.acceptedKey))
    }

    func testLoginLinkWaitsForConsentAndDoesNotGoOnline() async {
        let stub = JetBoxLoginStub()
        stub.replies["verify"] = (200, #"{"connect_url":"jetbox://connect#k=\#(key)&n=Demo%20Home"}"#)
        let flow = JetBoxOnboarding()
        flow.loginAPI = stub.api()
        var consent = false
        flow.needsDataConsent = { !consent }
        let link = URL(string: "https://\(JetBoxConfig.loginLinkHost)/auth/verify#t=\(token)")!

        XCTAssertTrue(flow.handle(link), "ссылка наша — её не отдают дальше по цепочке")
        XCTAssertEqual(flow.step, .idle)
        XCTAssertTrue(stub.requests.isEmpty, "до согласия в сеть не ходим")

        consent = true
        flow.resumeAfterDataConsent()
        XCTAssertEqual(flow.step, .signingIn)
        for _ in 0..<100 where flow.step == .signingIn {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        guard case .ready = flow.step else { return XCTFail("шаг \(flow.step)") }
    }

    func testForeignLinkIsNotHeld() {
        let flow = JetBoxOnboarding()
        flow.needsDataConsent = { true }
        XCTAssertFalse(flow.handle(URL(string: "jetbox://app/connect")!))
        XCTAssertFalse(flow.handle(URL(string: "https://example.com/connect")!), "без ключа — не ссылка подключения")
        #if !JETBOX_US
        XCTAssertFalse(flow.handle(URL(string: "https://example.com/connect#k=\(key)")!))
        #endif
    }
}

/// Сборка 1.0 (18): адреса серверов — только из конфига редакции.
final class JetBoxServersTests: XCTestCase {
    func testAddressesComeFromTheEditionConfig() {
        for value in [JetBoxServers.managementURL, JetBoxServers.apiBaseURL,
                      JetBoxServers.loginLinkHost, JetBoxServers.probeName] {
            XCTAssertFalse(value.isEmpty)
            XCTAssertFalse(value.contains("$("), "настройка сборки не подставилась: \(value)")
        }
        XCTAssertTrue(JetBoxServers.managementURL.hasPrefix("https://"))
        XCTAssertTrue(JetBoxServers.apiBaseURL.hasPrefix("https://"))
        #if JETBOX_US
        XCTAssertTrue(JetBoxServers.managementSuffix.isEmpty, "в США маски нет")
        #else
        XCTAssertTrue(JetBoxServers.managementSuffix.hasPrefix("."))
        #endif
    }

    #if JETBOX_US
    func testUSBuildHasNoRussianOrUpstreamAddresses() {
        let all = [JetBoxServers.managementURL, JetBoxServers.apiBaseURL,
                   JetBoxServers.loginLinkHost, JetBoxServers.probeName,
                   JetBoxConfig.defaultManagementURL, JetBoxConfig.loginAPIBase.absoluteString]
        for value in all {
            XCTAssertFalse(value.contains("jet-net"), value)
            XCTAssertFalse(value.contains("xn--"), value)
            XCTAssertFalse(value.contains("netbird.io"), value)
            XCTAssertTrue(value.contains("ai-boss.us"), value)
        }
    }

    /// Решение владельца 23.11.2026: в США фильтра по доменам в ссылке нет —
    /// ни маски `m`, ни проверки хоста ссылки (https или своя схема).
    func testUSBuildAcceptsLinksFromAnyHostWithAnyManagement() {
        let k = "11111111-2222-4333-8444-555555555555"
        XCTAssertTrue(JetBoxLinkRules.current.anyHost)
        // 1.0 (25): извне — только подписанные (JetBox safety); хост и сервер любые.
        JBSign.trustTestKey()
        defer { JBSign.forgetTestKey() }
        for raw in ["https://jetbox.ai-boss.us/connect#k=\(k)",
                    "https://example.com/any/path#k=\(k)&m=https%3A%2F%2Fmgmt.example.org%3A33073&e=home",
                    "jetbox://connect#k=\(k)&m=https://netbird.jet-net.net",
                    "jetbox://open#k=\(k)&m=https%3A%2F%2F100.64.0.1"] {
            XCTAssertEqual(JetBoxLink.parse(URL(string: raw)!), .unsigned, raw)
            guard case .payload = JetBoxLink.parse(URL(string: JBSign.sign(raw))!) else { return XCTFail(raw) }
        }
        guard case .payload(let p) = JetBoxLink.parse(URL(string: JBSign.sign("https://x.example/c#k=\(k)&m=https%3A%2F%2FMgmt.Example.ORG%3A33073%2F"))!) else {
            return XCTFail("payload")
        }
        XCTAssertEqual(p.managementURL, "https://mgmt.example.org:33073")
        // Без ключа это не ссылка подключения; кривой `m` и ключ — «повреждена».
        XCTAssertEqual(JetBoxLink.parse(URL(string: "https://example.com/connect")!), .notOurs)
        XCTAssertEqual(JetBoxLink.parse(URL(string: "jetbox://app/connect")!), .notOurs)
        XCTAssertEqual(JetBoxLink.parse(URL(string: JBSign.sign("jetbox://connect#k=\(k)&m=http://mgmt.example.org"))!), .broken)
        XCTAssertEqual(JetBoxLink.parse(URL(string: JBSign.sign("https://example.com/#k=bad"))!), .broken)
        // Ссылка входа из письма — тоже с любого хоста, путь /auth/verify.
        let t = "abcdefghijklmnopqrstuvwx"
        XCTAssertEqual(JetBoxLoginLink.parse(URL(string: "https://mail-redirect.example/auth/verify#t=\(t)")!), .token(t))
    }
    #endif
}

/// 1.0 (24): первый запуск — «простое», выбранное раньше «техно» не перетирается.
final class JetBoxStyleDefaultTests: XCTestCase {
    #if JETBOX_US
    func testFirstLaunchIsSimpleAndChosenTechnoStays() {
        let suite = "jetbox.tests.style.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(JetBoxStyle.current(in: defaults), .simple)
        defaults.set(JetBoxStyle.techno.rawValue, forKey: JetBoxStyle.key)
        XCTAssertEqual(JetBoxStyle.current(in: defaults), .techno)
        defaults.set("garbage", forKey: JetBoxStyle.key)
        XCTAssertEqual(JetBoxStyle.current(in: defaults), .simple)
        XCTAssertTrue(JetBoxStyle.isSelectable)
    }
    #else
    /// Русская сборка: «простого» нет — всегда «техно», даже если в App Group
    /// осталось «simple» от прежней версии; выбора стиля нет.
    func testRussianBuildIsAlwaysTechno() {
        let suite = "jetbox.tests.style.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(JetBoxStyle.current(in: defaults), .techno)
        defaults.set(JetBoxStyle.simple.rawValue, forKey: JetBoxStyle.key)
        XCTAssertEqual(JetBoxStyle.current(in: defaults), .techno)
        XCTAssertFalse(JetBoxStyle.isSelectable)
        XCTAssertEqual(JetBoxStyle.fallback, .techno)
    }
    #endif
}

/// Сборка 26 (решение Алексея 23.11.2026): в сборке США подписанная ссылка
/// подключает сразу — без экрана подтверждения, без вопроса о замене и без
/// экрана «готово». Русская сборка — как раньше, с кнопкой.
@MainActor
final class JetBoxAutoConnectTests: XCTestCase {
    private let key = "11111111-2222-4333-8444-555555555555"
    private let otherKey = "99999999-8888-4777-8666-555555555555"
    private var savedBox: JetBoxBox?

    override func setUp() {
        savedBox = JetBoxStore.currentBox
        JetBoxStore.currentBox = nil
    }

    override func tearDown() {
        JetBoxStore.currentBox = savedBox
    }

    private func link(_ key: String, name: String = "Demo Home") -> URL {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
        return URL(string: "jetbox://connect#k=\(key)&m=https%3A%2F%2F\(JBT.mgmtHost)&n=\(encoded)")!
    }

    private func payload(_ key: String, name: String) -> JetBoxLinkPayload {
        guard case .payload(let p) = JetBoxLink.parse(link(key, name: name), rules: .current.trustingSource) else {
            fatalError("ссылка не разобралась")
        }
        return p
    }

    private func flow(autoConnects: Bool) -> JetBoxOnboarding {
        let flow = JetBoxOnboarding()
        flow.needsDataConsent = { false }
        flow.autoConnects = autoConnects
        return flow
    }

    func testEditionDefault() {
        #if JETBOX_US
        XCTAssertTrue(JetBoxOnboarding.editionAutoConnects)
        #else
        XCTAssertFalse(JetBoxOnboarding.editionAutoConnects)
        #endif
    }

    /// Первый вход: без экрана — шаг ждёт ViewModel и сразу стартует,
    /// главный экран показывает коробку из ссылки и «Connecting…».
    func testFirstLinkConnectsWithoutAScreen() {
        let flow = flow(autoConnects: true)
        XCTAssertTrue(flow.handle(link(key), trusted: true))
        guard case .ready(let p) = flow.step else { return XCTFail("шаг \(flow.step)") }
        XCTAssertEqual(p.boxName, "Demo Home")
        XCTAssertFalse(flow.isPresenting, "экрана подтверждения нет")
        XCTAssertTrue(flow.isConnectingInBackground)
        XCTAssertEqual(flow.connectingBox?.displayName, "Demo Home")
        XCTAssertFalse(JetBoxEdition.showsEmailLogin(homeOnly: true, box: flow.connectingBox ?? JetBoxStore.currentBox),
                       "пока идёт подключение, форма входа не показывается")
    }

    /// Ссылка на другую коробку — замена без вопроса.
    func testOtherBoxIsReplacedWithoutAQuestion() {
        JetBoxStore.remember(payload(key, name: "Old Home"))
        let flow = flow(autoConnects: true)
        XCTAssertTrue(flow.handle(link(otherKey, name: "New Home"), trusted: true))
        guard case .ready(let p) = flow.step else { return XCTFail("шаг \(flow.step)") }
        XCTAssertEqual(p.boxName, "New Home")
        XCTAssertFalse(flow.isPresenting)
        XCTAssertEqual(flow.connectingBox?.displayName, "New Home", "главный экран — уже про новую коробку")
    }

    /// Ссылка на ту же коробку — без регистрации: главный экран, а
    /// выключенный туннель включается (клик по ссылке = подключение).
    func testSameBoxTurnsTunnelOnAndShowsHome() {
        JetBoxStore.remember(payload(key, name: "Demo Home"))
        let flow = flow(autoConnects: true)
        var resumed = 0
        flow.resumeTunnel = { resumed += 1; return true }
        XCTAssertTrue(flow.handle(link(key), trusted: true))
        XCTAssertEqual(flow.step, .idle)
        XCTAssertEqual(resumed, 1, "туннель включаем через обычное подключение, без регистрации")
        XCTAssertFalse(flow.isConnectingInBackground)
        XCTAssertNil(flow.connectingBox)
    }

    /// Другая коробка и первый вход идут через регистрацию, а не через
    /// простое включение туннеля.
    func testOnlySameBoxResumesTunnel() {
        let flow = flow(autoConnects: true)
        var resumed = 0
        flow.resumeTunnel = { resumed += 1; return true }
        XCTAssertTrue(flow.handle(link(key), trusted: true))
        JetBoxStore.remember(payload(key, name: "Old Home"))
        XCTAssertTrue(flow.handle(link(otherKey, name: "New Home"), trusted: true))
        XCTAssertEqual(resumed, 0)
    }

    /// Отказы по-прежнему на экране — и неподписанная ссылка в США.
    func testFailuresStillShowAScreen() {
        let flow = flow(autoConnects: true)
        XCTAssertTrue(flow.handle(URL(string: "jetbox://connect#k=not-a-key")!, trusted: true))
        XCTAssertEqual(flow.step, .failed(.brokenLink))
        XCTAssertTrue(flow.isPresenting)
        XCTAssertFalse(flow.isConnectingInBackground)
        #if JETBOX_US
        XCTAssertTrue(flow.handle(link(key)))
        XCTAssertEqual(flow.step, .failed(.notFromJetBox), "без подписи — отказ до подключения")
        XCTAssertTrue(flow.isPresenting)
        #endif
    }

    /// Русская сборка: экран с кнопкой и вопрос о замене остаются.
    func testManualFlowKeepsConfirmAndSwitch() {
        let flow = flow(autoConnects: false)
        flow.resumeTunnel = { XCTFail("русская сборка туннель по ссылке сама не включает"); return false }
        XCTAssertTrue(flow.handle(link(key), trusted: true))
        guard case .ready = flow.step else { return XCTFail("шаг \(flow.step)") }
        XCTAssertTrue(flow.isPresenting)
        XCTAssertFalse(flow.isConnectingInBackground)

        JetBoxStore.remember(payload(key, name: "Old Home"))
        XCTAssertTrue(flow.handle(link(otherKey, name: "New Home"), trusted: true))
        guard case .confirmSwitch(_, let current) = flow.step else { return XCTFail("шаг \(flow.step)") }
        XCTAssertEqual(current, "Old Home")
    }
}

/// Сборка 29 (Алексей, 23.11.2026): в Settings → Legal и в About сборки США —
/// два пункта, User agreement (Terms of Use, #terms) и Privacy policy; внизу About —
/// «© <год> INSTASHOP Corporation».
final class JetBoxUSLegalLinksTests: XCTestCase {
    func testTwoItemsAndTheirAddresses() {
        XCTAssertEqual(JBText.legalUSAgreement, "User agreement")
        XCTAssertEqual(JBText.legalUSPrivacy, "Privacy policy")
        XCTAssertEqual(JetBoxConfig.termsURL.absoluteString, "https://jetbox.ai-boss.us/legal/#terms")
        XCTAssertEqual(JetBoxConfig.privacyPolicyURL.absoluteString, "https://jetbox.ai-boss.us/legal/#privacy")
    }

    func testConsentLineNamesTheSameDocuments() {
        #if JETBOX_US
        XCTAssertEqual(JBText.legalConsent,
                       "By continuing, you agree to the [User agreement](https://jetbox.ai-boss.us/legal/#terms) and [Privacy policy](https://jetbox.ai-boss.us/legal/#privacy).")
        #endif
    }

    func testUSProtectedTitle() {
        #if JETBOX_US
        XCTAssertEqual(JBText.homeConnectedAll, "You are in your home network, protected by JetBox")
        XCTAssertEqual(JBText.protectedTitleAll, "You are in your home network, protected by JetBox")
        #endif
    }

    func testUSCopyrightLine() {
        XCTAssertEqual(JBText.aboutCopyrightUS("2026"), "© 2026 INSTASHOP Corporation")
    }
}


/// Сборка 32: объяснение перед системным запросом iOS и правдивые тексты.
@MainActor
final class JetBoxVPNExplainTests: XCTestCase {
    func testNoProfileShowsExplanationAndContinueGoesOn() async {
        let flow = JetBoxOnboarding()
        flow.explainsVPN = true
        flow.vpnProfileExists = { false }
        let task = Task { await flow.explainVPNIfNeeded() }
        for _ in 0..<50 where flow.step != .explainVPN { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(flow.step, .explainVPN)
        XCTAssertTrue(flow.isPresenting, "экран поверх главного")
        flow.continueAfterVPNExplain()
        let go = await task.value
        XCTAssertTrue(go)
        XCTAssertEqual(flow.step, .idle, "после Continue — прежний шаг")
    }

    func testProfileExistsSkipsExplanation() async {
        let flow = JetBoxOnboarding()
        flow.explainsVPN = true
        flow.vpnProfileExists = { true }
        let go = await flow.explainVPNIfNeeded()
        XCTAssertTrue(go)
        XCTAssertEqual(flow.step, .idle)
    }

    func testDismissCancelsWaitingFlow() async {
        let flow = JetBoxOnboarding()
        flow.explainsVPN = true
        flow.vpnProfileExists = { false }
        let task = Task { await flow.explainVPNIfNeeded() }
        for _ in 0..<50 where flow.step != .explainVPN { try? await Task.sleep(nanoseconds: 10_000_000) }
        flow.dismiss()
        let go = await task.value
        XCTAssertFalse(go)
    }

    func testRussianEditionNeverExplains() async {
        let flow = JetBoxOnboarding()
        flow.explainsVPN = false
        flow.vpnProfileExists = { XCTFail("без экрана профиль не спрашиваем"); return false }
        let go = await flow.explainVPNIfNeeded()
        XCTAssertTrue(go)
    }

    func testTexts() throws {
        try XCTSkipUnless(JetBoxEdition.homeOnly, "английские тексты — сборка США")
        XCTAssertEqual(JBText.vpnExplainTitle, "Allow the VPN configuration")
        XCTAssertEqual(JBText.vpnExplainContinue, "Continue")
        XCTAssertTrue(JBText.vpnExplainBody.hasPrefix("JetBox Home adds a VPN configuration to this iPhone."))
        XCTAssertTrue(JBText.vpnExplainBody.hasSuffix("Next, iOS will ask for your permission."))
        XCTAssertEqual(JBText.settingsDeleteTitle, "Delete account?")
        XCTAssertTrue(JBText.settingsDeleteBody.contains("erased within 30 days"))
        XCTAssertEqual(JBText.deleteDone, "Account deleted")
        XCTAssertEqual(JBText.deleteLastOwnerBody("dev@ai-boss.us"),
                       "You’re the only owner of this JetBox, so the account can’t be deleted in the app. Write to us at dev@ai-boss.us and we’ll take care of it.")
        XCTAssertFalse(JBText.privacyNotice.contains("app version"))
    }
}

// MARK: - «Sign out» с освобождением места (1.0 (33), паритет с Android)

@MainActor
final class JetBoxSignOutRevokeTests: XCTestCase {
    private var savedBox: JetBoxBox?
    private var token: String?

    override func setUp() async throws {
        savedBox = JetBoxStore.currentBox
        token = nil
    }

    override func tearDown() async throws {
        JetBoxStore.currentBox = savedBox
    }

    private func flow(_ stub: JetBoxLoginStub) -> JetBoxOnboarding {
        let flow = JetBoxOnboarding()
        flow.needsDataConsent = { false }
        flow.loginAPI = stub.api()
        flow.loadAppToken = { [unowned self] in self.token }
        flow.deleteAppToken = { [unowned self] in self.token = nil }
        flow.revokeRetryDelay = 0
        JetBoxStore.currentBox = JetBoxBox(managementURL: "https://netbird.jet-net.net", exitNodeName: "home-ivanov",
                                           selectedExitNode: "home-ivanov", boxName: "Lakeview Home", registeredAt: Date())
        return flow
    }

    func testRevokeBeforeTunnelStopsThenSignsOut() async {
        let stub = JetBoxLoginStub()
        stub.replies["revoke"] = (200, #"{"ok":true}"#)
        let flow = flow(stub)
        token = "app-token-123"
        var stoppedAfterRequests: Int?
        let result = await flow.signOutReleasingPlace(stopTunnel: { stoppedAfterRequests = stub.requests.count },
                                                      files: nil)
        XCTAssertEqual(result, .signedOut)
        XCTAssertEqual(stub.requests.count, 1)
        XCTAssertEqual(stub.requests.first?.url?.absoluteString, "\(JBT.api)device/revoke")
        XCTAssertEqual(stub.requests.first?.httpMethod, "POST")
        XCTAssertEqual(stub.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer app-token-123")
        XCTAssertEqual(stub.requests.first?.timeoutInterval, 15)
        XCTAssertEqual(stoppedAfterRequests, 1, "туннель выключается только после ответа Кабинета")
        XCTAssertNil(JetBoxStore.currentBox)
        XCTAssertNil(token)
        XCTAssertEqual(flow.signOutCount, 1)
        XCTAssertFalse(stub.logs.joined().contains("app-token-123"), "токен в журнал не пишем")
    }

    func testUnknownToken401SignsOut() async {
        let stub = JetBoxLoginStub()
        stub.replies["revoke"] = (401, #"{"error":"bad_token"}"#)
        let flow = flow(stub)
        token = "old"
        let result = await flow.signOutReleasingPlace(stopTunnel: {}, files: nil)
        XCTAssertEqual(result, .signedOut)
        XCTAssertNil(JetBoxStore.currentBox)
    }

    func testNoTokenSignsOutOnThisPhoneWithoutRequest() async {
        let stub = JetBoxLoginStub()
        let flow = flow(stub)
        let result = await flow.signOutReleasingPlace(stopTunnel: {}, files: nil)
        XCTAssertEqual(result, .signedOut)
        XCTAssertTrue(stub.requests.isEmpty, "вход по ссылке — токена нет, освобождать нечем")
        XCTAssertNil(JetBoxStore.currentBox)
    }

    /// 502 / 429 — ответ есть, устройство живо: ничего не тронуто, решает человек.
    func testServerRefusalKeepsEverythingAndAsks() async {
        for code in [502, 429] {
            let stub = JetBoxLoginStub()
            stub.replies["revoke"] = (code, #"{"error":"unavailable"}"#)
            let flow = flow(stub)
            token = "app-token"
            var stopped = false
            let result = await flow.signOutReleasingPlace(stopTunnel: { stopped = true }, files: nil)
            XCTAssertEqual(result, .serverDidNotAnswer, "\(code)")
            XCTAssertEqual(stub.requests.count, 1, "на отказ без автоповтора")
            XCTAssertFalse(stopped, "\(code): туннель не трогаем")
            XCTAssertNotNil(JetBoxStore.currentBox)
            XCTAssertEqual(token, "app-token")
            XCTAssertEqual(flow.signOutCount, 0)
        }
    }

    /// Кабинет отозвал устройство, туннель упал, ответ потерян: туннель выключаем,
    /// повтор идёт напрямую, погашенный токен отвечает 200 — это успех.
    func testLostAnswerStopsTunnelAndRetriesDirectly() async {
        let stub = JetBoxLoginStub()
        stub.dropFirst = 1
        stub.replies["revoke"] = (200, #"{"ok":true}"#)
        let flow = flow(stub)
        token = "app-token"
        var stopsBeforeRetry: Int?
        var stops = 0
        let result = await flow.signOutReleasingPlace(stopTunnel: {
            stops += 1
            if stopsBeforeRetry == nil { stopsBeforeRetry = stub.requests.count }
        }, files: nil)
        XCTAssertEqual(result, .signedOut)
        XCTAssertEqual(stub.requests.count, 2, "один автоматический повтор")
        XCTAssertEqual(stopsBeforeRetry, 1, "туннель выключен между первым запросом и повтором")
        XCTAssertNil(JetBoxStore.currentBox)
    }

    func testBothAttemptsLostAsksAndKeepsAccount() async {
        let stub = JetBoxLoginStub()
        stub.dropFirst = 2
        let flow = flow(stub)
        token = "app-token"
        let result = await flow.signOutReleasingPlace(stopTunnel: {}, files: nil)
        XCTAssertEqual(result, .serverDidNotAnswer)
        XCTAssertNotNil(JetBoxStore.currentBox, "запись цела — «Try again» или «only on this iPhone»")
        XCTAssertEqual(token, "app-token")

        // «Sign out on this iPhone only» — локальный выход, место остаётся занятым.
        await flow.signOut(stopTunnel: {}, files: nil)
        XCTAssertNil(JetBoxStore.currentBox)
        XCTAssertNil(token)
        XCTAssertEqual(stub.requests.count, 2, "локальный выход в Кабинет не ходит")
    }

    func testApprovedTexts() {
        XCTAssertEqual(JBText.signOutFailedTitle, "Couldn’t sign out")
        XCTAssertEqual(JBText.signOutFailedBody,
                       "JetBox didn’t answer, so this iPhone still counts toward your device limit. Try again, or sign out on this iPhone only — then remove it later in your account.")
        XCTAssertEqual(JBText.signOutTryAgain, "Try again")
        XCTAssertEqual(JBText.signOutThisPhoneOnly, "Sign out on this iPhone only")
        XCTAssertEqual(JBText.loginNotAvailable, "Your JetBox isn’t online yet. Try again once it’s set up.")
        #if JETBOX_US
        XCTAssertEqual(JBText.errDeviceLimitBody,
                       "You’ve reached the device limit for this account. Sign out on another device to free up a place.")
        #endif
    }
}

// MARK: - Проба DNS канарейкой (1.0 (34))

@MainActor
final class JetBoxDNSCheckTests: XCTestCase {
    /// Ответ DNS: заголовок, вопрос, ответы A (имя ответа — указатель на вопрос).
    private func response(id: UInt16, rcode: UInt8 = 0, addresses: [[UInt8]] = []) -> Data {
        var b: [UInt8] = [UInt8(id >> 8), UInt8(id & 0xFF), 0x81, 0x80 | rcode, 0, 1, 0, UInt8(addresses.count), 0, 0, 0, 0]
        for label in JetBoxDNSCheck.canaryName.split(separator: ".") {
            b.append(UInt8(label.utf8.count)); b.append(contentsOf: label.utf8)
        }
        b.append(contentsOf: [0, 0, 1, 0, 1])
        for a in addresses {
            b.append(contentsOf: [0xC0, 0x0C, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4])
            b.append(contentsOf: a)
        }
        return Data(b)
    }

    func testParseMarkAnswer() {
        XCTAssertEqual(JetBoxDNSCheck.parseA(response(id: 7, addresses: [[192, 0, 2, 53]]), id: 7),
                       .addresses(["192.0.2.53"]))
        XCTAssertTrue(JetBoxDNSCheck.parseA(response(id: 7, addresses: [[1, 2, 3, 4], [192, 0, 2, 53]]), id: 7).hasMark)
    }

    func testParseNXDOMAINServfailAndForeignID() {
        XCTAssertEqual(JetBoxDNSCheck.parseA(response(id: 9, rcode: 3), id: 9), .nxdomain)
        XCTAssertEqual(JetBoxDNSCheck.parseA(response(id: 9, rcode: 2), id: 9), .noAnswer)
        XCTAssertEqual(JetBoxDNSCheck.parseA(response(id: 9, addresses: [[192, 0, 2, 53]]), id: 10), .noAnswer)
        XCTAssertEqual(JetBoxDNSCheck.parseA(Data([1, 2, 3]), id: 1), .noAnswer)
        XCTAssertEqual(JetBoxDNSCheck.parseA(response(id: 9), id: 9), .addresses([]))
    }

    func testCanaryNameIsMarketDomainOnly() {
        #if JETBOX_US
        XCTAssertEqual(JetBoxDNSCheck.canaryName, "dnscheck.jetbox.ai-boss.us")
        #endif
        XCTAssertEqual(JetBoxDNSCheck.nonceName("abc123"), "abc123.\(JetBoxDNSCheck.canaryName)")
        XCTAssertEqual(JetBoxDNSCheck.randomNonce().count, 12)
    }

    func testVerdicts() {
        let mark = JetBoxDNSAnswer.addresses(["192.0.2.53"])
        XCTAssertEqual(JetBoxDNSCheck.verdict(box: mark, system: mark), .throughBox)
        XCTAssertEqual(JetBoxDNSCheck.verdict(box: mark, system: .nxdomain), .bypassed)
        XCTAssertEqual(JetBoxDNSCheck.verdict(box: mark, system: .addresses(["8.8.8.8"])), .bypassed)
        XCTAssertEqual(JetBoxDNSCheck.verdict(box: mark, system: .noAnswer), .noAnswer)
        XCTAssertEqual(JetBoxDNSCheck.verdict(box: .nxdomain, system: .nxdomain), .boxDoesNotKnow)
        XCTAssertEqual(JetBoxDNSCheck.verdict(box: .noAnswer, system: mark), .boxDoesNotKnow)
    }

    /// Резолверы-подмены: ответ по имени, журнал вопросов.
    private final class Asked: @unchecked Sendable { var box: [String] = []; var system: [String] = [] }

    private func resolvers(_ asked: Asked, box: @escaping (String) -> JetBoxDNSAnswer,
                           system: @escaping (String) -> JetBoxDNSAnswer) -> JetBoxDNSCheck.Resolvers {
        JetBoxDNSCheck.Resolvers(box: { host, name in
            XCTAssertEqual(host, "100.64.0.1")
            asked.box.append(name); return box(name)
        }, system: { name in asked.system.append(name); return system(name) })
    }

    func testNonceFirstThenExactName() async {
        let asked = Asked()
        let mark = JetBoxDNSAnswer.addresses(["192.0.2.53"])
        // Коробка знает только точное имя (до поддоменов), система — тоже через коробку.
        let verdict = await JetBoxDNSCheck.run(host: "100.64.0.1", resolvers: resolvers(asked,
            box: { $0 == JetBoxDNSCheck.canaryName ? mark : .nxdomain },
            system: { $0 == JetBoxDNSCheck.canaryName ? mark : .noAnswer }), nonce: "n1")
        XCTAssertEqual(verdict, .throughBox)
        XCTAssertEqual(asked.box, ["n1.\(JetBoxDNSCheck.canaryName)", JetBoxDNSCheck.canaryName])
        XCTAssertEqual(asked.system, ["n1.\(JetBoxDNSCheck.canaryName)", JetBoxDNSCheck.canaryName])
    }

    func testMarkOnNonceSkipsExactName() async {
        let asked = Asked()
        let mark = JetBoxDNSAnswer.addresses(["192.0.2.53"])
        let verdict = await JetBoxDNSCheck.run(host: "100.64.0.1", resolvers: resolvers(asked,
            box: { _ in mark }, system: { _ in .nxdomain }), nonce: "n2")
        XCTAssertEqual(verdict, .bypassed)
        XCTAssertEqual(asked.box.count, 1)
        XCTAssertEqual(asked.system.count, 2, "без метки на случайном — точное имя")
    }

    func testOldBoxIsSilentAndSystemNotAsked() async {
        let asked = Asked()
        let verdict = await JetBoxDNSCheck.run(host: "100.64.0.1", resolvers: resolvers(asked,
            box: { _ in .nxdomain }, system: { _ in .nxdomain }), nonce: "n3")
        XCTAssertEqual(verdict, .boxDoesNotKnow)
        XCTAssertTrue(asked.system.isEmpty, "коробка канарейку не знает — проверки нет")
    }

    func testCombinePrefersMarkThenDefiniteAnswer() {
        let mark = JetBoxDNSAnswer.addresses(["192.0.2.53"])
        XCTAssertEqual(JetBoxDNSCheck.combine(nonce: .nxdomain, exact: mark), mark)
        XCTAssertEqual(JetBoxDNSCheck.combine(nonce: .nxdomain, exact: .noAnswer), .nxdomain)
        XCTAssertEqual(JetBoxDNSCheck.combine(nonce: .noAnswer, exact: .nxdomain), .nxdomain)
    }

    func testLiveStatsChecksOncePerIntervalAndAfterReconnect() async {
        let stats = JetBoxLiveStats()
        var runs = 0
        stats.runDNSCheck = { _ in runs += 1; return .bypassed }
        let start = Date()
        stats.checkDNSIfDue(host: "100.64.0.1", now: start)
        for _ in 0..<20 where stats.dnsVerdict == nil { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(stats.dnsVerdict, .bypassed)
        stats.checkDNSIfDue(host: "100.64.0.1", now: start.addingTimeInterval(60))
        XCTAssertEqual(runs, 1, "раз в 10 минут")
        stats.checkDNSIfDue(host: "100.64.0.1", now: start.addingTimeInterval(601))
        for _ in 0..<20 where runs < 2 { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(runs, 2)
    }
}

// MARK: - «Help» (1.0 (34))

@MainActor
final class JetBoxHelpTests: XCTestCase {
    private let defaults = UserDefaults(suiteName: "jetbox-help-tests")!

    override func setUp() async throws {
        defaults.removePersistentDomain(forName: "jetbox-help-tests")
    }

    func testSupportSendsContractAndRemembersEmail() async {
        let stub = JetBoxLoginStub()
        stub.replies["support"] = (200, #"{"ok":true,"promise":"We reply within a day.","support_email":"help@ai-boss.us"}"#)
        let saved = JetBoxAdvancedAccess.defaults.string(forKey: JetBoxSupportContact.key)
        defer { JetBoxAdvancedAccess.defaults.set(saved, forKey: JetBoxSupportContact.key) }
        let outcome = await stub.api().sendSupport(token: "tok-1", message: "Nothing happens", diagnostics: "App: x",
                                                   version: "1.0 (34)", lang: "en")
        XCTAssertEqual(outcome, .sent(promise: "We reply within a day."))
        XCTAssertEqual(stub.requests.first?.url?.absoluteString, "\(JBT.api)support")
        XCTAssertEqual(stub.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer tok-1")
        XCTAssertEqual(stub.body(0), ["message": "Nothing happens", "diagnostics": "App: x", "platform": "ios",
                                      "version": "1.0 (34)", "lang": "en"])
        XCTAssertEqual(JetBoxSupportContact.current(), "help@ai-boss.us")
        XCTAssertFalse(stub.logs.joined().contains("tok-1"))
    }

    func testSupportOutcomes() async {
        let stub = JetBoxLoginStub()
        for (code, expected) in [(429, JetBoxLoginAPI.SupportOutcome.rateLimited), (401, .needsMail),
                                 (413, .needsMail), (502, .needsMail)] {
            stub.replies["support"] = (code, #"{"error":"x"}"#)
            let outcome = await stub.api().sendSupport(token: "t", message: "m", diagnostics: "", version: "v", lang: "en")
            XCTAssertEqual(outcome, expected, "\(code)")
        }
        stub.replies["support"] = (200, #"{"ok":true}"#)
        let noPromise = await stub.api().sendSupport(token: "t", message: "m", diagnostics: "", version: "v", lang: "en")
        XCTAssertEqual(noPromise, .sent(promise: nil))
        stub.error = URLError(.notConnectedToInternet)
        let offline = await stub.api().sendSupport(token: "t", message: "m", diagnostics: "", version: "v", lang: "en")
        XCTAssertEqual(offline, .needsMail)
    }

    func testSupportCutsLongTexts() async {
        let stub = JetBoxLoginStub()
        stub.replies["support"] = (200, "{}")
        _ = await stub.api().sendSupport(token: "t", message: String(repeating: "a", count: 5000),
                                         diagnostics: String(repeating: "d", count: 20000), version: "v", lang: "en")
        XCTAssertEqual(stub.body(0)["message"]?.count, 4000)
        XCTAssertEqual(stub.body(0)["diagnostics"]?.count, 16000)
    }

    func testContactKeepsOnlyEmailsAndFallsBack() {
        XCTAssertEqual(JetBoxSupportContact.current(defaults: defaults), JetBoxOnboarding.defaultSupportEmail)
        JetBoxSupportContact.remember("+7 495 000-00-00", defaults: defaults)
        XCTAssertEqual(JetBoxSupportContact.current(defaults: defaults), "dev@ai-boss.us", "телефон — не адрес")
        JetBoxSupportContact.remember(" team@ai-boss.us ", defaults: defaults)
        XCTAssertEqual(JetBoxSupportContact.current(defaults: defaults), "team@ai-boss.us")
    }

    func testScrubRemovesSecrets() {
        let line = "[2026-11-28T09:00:00.000Z] [JetBoxOnboarding.swift:10] JetBox: link jetbox://connect#k=11111111-2222-4333-8444-555555555555&m=https://net.jetbox.ai-boss.us&s=AbCdEf0123456789AbCdEf0123456789AbCdEf0123456789AbCdEf0123456789AbCd peer key 6bVg0eWfXmT3kZ2pQ9rS8tU7vW6xY5zA4bC3dE2fG1h= token Zq3vX9_kL2-mN8pR4tW6yA0bC5dE7fG1hJ email alex.smith@example.com ip 203.0.113.9 mesh 100.79.1.2 lan 192.168.1.5 mark 192.0.2.53 id 0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D"
        let clean = JetBoxDiagnostics.scrub(line)
        for secret in ["11111111-2222", "net.jetbox.ai-boss.us", "AbCdEf0123456789", "6bVg0eWfXmT3kZ2pQ9rS8tU7vW6xY5zA4bC3dE2fG1h=",
                       "Zq3vX9_kL2-mN8pR4tW6yA0bC5dE7fG1hJ", "alex.smith", "203.0.113.9", "0A1B2C3D-4E5F"] {
            XCTAssertFalse(clean.contains(secret), "осталось «\(secret)»: \(clean)")
        }
        for kept in ["JetBox: link", "al***@example.com", "100.79.1.2", "192.168.1.5", "192.0.2.53", "JetBoxOnboarding.swift:10"] {
            XCTAssertTrue(clean.contains(kept), "пропало «\(kept)»: \(clean)")
        }
    }

    func testLastJetBoxLinesFiltersAndLimits() {
        var log = (1...70).map { "[t] [F.swift:1] JetBox: line \($0)" }
        log.insert("[t] [G.swift:2] engine: noise", at: 3)
        let lines = JetBoxDiagnostics.lastJetBoxLines(log.joined(separator: "\n"))
        XCTAssertEqual(lines.count, 50)
        XCTAssertEqual(lines.last, "[t] [F.swift:1] JetBox: line 70")
        XCTAssertFalse(lines.contains { $0.contains("engine") })
    }

    func testDiagnosticsTextHasNoSecretsByConstruction() {
        let facts = JetBoxDiagnostics.Facts(appVersion: "1.0 (34)", osVersion: "26.1", language: "en-US", signIn: "email",
                                            maskedEmail: JetBoxDiagnostics.maskEmail("alex@example.com"), hasToken: true,
                                            tunnel: "connected", homeAnswers: true, latencyMs: 24, route: "direct",
                                            uptime: "4:05", exit: nil, dns: JetBoxDNSVerdict.bypassed.diagnostics)
        let text = JetBoxDiagnostics.text(facts, log: [])
        XCTAssertTrue(text.contains("Sign-in: email, al***@example.com"))
        XCTAssertTrue(text.contains("Home answers: yes, 24 ms"))
        XCTAssertTrue(text.contains("DNS: bypasses JetBox"))
        XCTAssertFalse(text.contains("alex@"))
    }

    func testMailURLCarriesSubjectAndDiagnostics() throws {
        let url = try XCTUnwrap(JetBoxDiagnostics.mailURL(to: "dev@ai-boss.us", appVersion: "1.0 (34)",
                                                         message: "No internet", diagnostics: "DNS: x"))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "mailto")
        XCTAssertEqual(parts.path, "dev@ai-boss.us")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "subject" }?.value, "JetBox: iOS 1.0 (34)")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "body" }?.value, "No internet\n\n--- Diagnostics ---\nDNS: x")
    }

    private func model(_ stub: JetBoxLoginStub, token: String?) -> JetBoxHelpModel {
        let model = JetBoxHelpModel(diagnostics: "App: test", appVersion: "1.0 (34)")
        model.api = stub.api()
        model.loadToken = { token }
        model.supportAddress = { "dev@ai-boss.us" }
        model.message = "Help"
        return model
    }

    func testNoTokenGoesStraightToMail() async {
        let stub = JetBoxLoginStub()
        let model = model(stub, token: nil)
        var opened: URL?
        await model.send { opened = $0; return true }
        XCTAssertTrue(stub.requests.isEmpty)
        XCTAssertEqual(opened?.scheme, "mailto")
        XCTAssertEqual(model.phase, .editing)
    }

    func testMailThatDoesNotOpenShowsAddress() async {
        let stub = JetBoxLoginStub()
        let model = model(stub, token: nil)
        await model.send { _ in false }
        XCTAssertEqual(model.phase, .mailFailed("dev@ai-boss.us"))
    }

    func testTokenSentShowsPromiseOrFallback() async {
        let stub = JetBoxLoginStub()
        stub.replies["support"] = (200, #"{"ok":true,"promise":"Within an hour."}"#)
        let first = model(stub, token: "t")
        await first.send { _ in XCTFail("письмо не нужно"); return true }
        XCTAssertEqual(first.phase, .sent("Within an hour."))
        stub.replies["support"] = (200, #"{"ok":true}"#)
        let second = model(stub, token: "t")
        await second.send { _ in true }
        XCTAssertEqual(second.phase, .sent(JBText.helpSentFallback))
    }

    func testRateLimitStaysOnFormAndRefusalFallsBackToMail() async {
        let stub = JetBoxLoginStub()
        stub.replies["support"] = (429, #"{"error":"rate_limited","retry_after":120}"#)
        let limited = model(stub, token: "t")
        await limited.send { _ in XCTFail("на 429 письма нет"); return true }
        XCTAssertEqual(limited.phase, .editing)
        XCTAssertEqual(limited.notice, JBText.helpRateLimited)
        stub.replies["support"] = (401, #"{"error":"bad_token"}"#)
        let refused = model(stub, token: "t")
        var mailed = false
        await refused.send { _ in mailed = true; return true }
        XCTAssertTrue(mailed)
    }

    func testEmptyMessageDoesNotSend() async {
        let stub = JetBoxLoginStub()
        let model = model(stub, token: "t")
        model.message = "   "
        XCTAssertFalse(model.canSend)
        await model.send { _ in XCTFail(); return true }
        XCTAssertTrue(stub.requests.isEmpty)
    }

    func testApprovedTexts() {
        XCTAssertEqual(JBText.dnsBypassed, "DNS doesn’t go through JetBox — ads and trackers aren’t filtered")
        XCTAssertEqual(JBText.dnsHowToFix, "How to fix")
        XCTAssertEqual(JBText.helpRow, "Help")
        XCTAssertEqual(JBText.helpTitle, "Contact us")
        XCTAssertEqual(JBText.helpPlaceholder, "Describe what happened")
        XCTAssertEqual(JBText.helpAttach, "Attach diagnostics")
        XCTAssertEqual(JBText.helpSend, "Send")
        XCTAssertEqual(JBText.helpSentFallback, "Sent. We’ll reply by email.")
        XCTAssertEqual(JBText.helpRateLimited, "You’ve already sent a message. Try again in a few minutes.")
        XCTAssertEqual(JBText.helpMailFailed("dev@ai-boss.us"), "Couldn’t send from the app. Write to us at dev@ai-boss.us.")
    }
}
