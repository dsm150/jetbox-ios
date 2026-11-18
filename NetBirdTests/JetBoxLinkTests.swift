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
                       JetBoxConfig.defaultManagementURL)
        XCTAssertEqual(payload("jetbox://connect#k=\(key)&m=")?.managementURL,
                       JetBoxConfig.defaultManagementURL)
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

    func testSharedCloudExitNeverMatchesWithoutName() {
        // Общий e облака: запись без имени не считаем «тем же» ни для какой ссылки.
        let cloudNoName = JetBoxBox(managementURL: "https://mgmt.jet-net.net", exitNodeName: "cl-exit",
                                    selectedExitNode: nil, boxName: nil, registeredAt: Date(timeIntervalSince1970: 0))
        let link = payload("jetbox://connect#k=\(key)&m=https://mgmt.jet-net.net&e=cl-exit&n=JetBox%20%C2%B7%20petr")!
        XCTAssertFalse(cloudNoName.isSameConnection(as: link))
        XCTAssertTrue(JetBoxLinkIdentity.isSharedExit("cl-exit"))
        XCTAssertFalse(JetBoxLinkIdentity.isSharedExit("sv-acme-exit"))
    }

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
            XCTAssertEqual(JetBoxLink.allowedManagement(c.m), c.ok, "\(c.m) — \(c.why)")
        }
    }

    func testForeignManagementIsRefusedBeforeAnything() {
        let link = URL(string: "https://box.jet-net.net/connect#k=\(key)&m=https%3A%2F%2Fevil.example.com&e=one")!
        XCTAssertEqual(JetBoxLink.parse(link), .foreignServer)
        let ip = URL(string: "jetbox://connect#k=\(key)&m=https%3A%2F%2F100.79.0.1%3A33073")!
        XCTAssertEqual(JetBoxLink.parse(ip), .foreignServer)
    }

    func testMaskedManagementWithPortIsAccepted() {
        let link = payload("jetbox://connect#k=\(key)&m=https%3A%2F%2Fnetbird.jet-net.net%3A33073&e=one")
        XCTAssertEqual(link?.managementURL, "https://netbird.jet-net.net:33073")
    }

    func testMissingManagementStillMeansDefault() {
        XCTAssertEqual(payload("jetbox://connect#k=\(key)&e=one")?.managementURL, JetBoxConfig.defaultManagementURL)
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
