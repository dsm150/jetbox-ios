//
//  JetBoxLinkSignatureTests.swift
//  NetBirdTests
//
//  JetBox safety v1 — подпись ссылки подключения (1.0 (25), сборка США).
//  Векторы — VPN_Box/docs/superpowers/specs/2026-11-23-link-signature-vectors.json,
//  на ТЕСТОВОМ ключе (закрытый = байты 0x00…0x1f). Боевого ключа здесь нет;
//  тестовый в приложение не попадает (testPublicKeys — только DEBUG).
//

import XCTest
import CryptoKit
@testable import NetBird

/// Подпись ссылок тестовым ключом векторов — для тестов, которым в сборке США
/// нужна подписанная ссылка.
enum JBSign {
    static let testPrivateKey = try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(0..<32))
    static var testPublicKeyB64: String { testPrivateKey.publicKey.rawRepresentation.base64EncodedString() }

    /// Разрешить тестовый ключ на время теста.
    static func trustTestKey() {
        JetBoxLinkSignature.testPublicKeys = [testPublicKeyB64]
    }

    static func forgetTestKey() {
        JetBoxLinkSignature.testPublicKeys = []
    }

    /// Дописать `&s=` к ссылке (фрагмент без `s`).
    static func sign(_ link: String) -> String {
        guard let hash = link.firstIndex(of: "#") else { return link }
        let fragment = String(link[link.index(after: hash)...])
        let unsigned = fragment + "&s=" + String(repeating: "A", count: 86)
        let signed = JetBoxLinkSignature.signedMessage(fragment: unsigned)!
        let sig = try! testPrivateKey.signature(for: signed.message)
        return link + "&s=" + base64URL(sig)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

final class JetBoxLinkSignatureTests: XCTestCase {
    struct Vector {
        let name: String
        let link: String
        let valid: Bool
        let messageB64: String?
    }

    static let testPublicKeyB64 = "A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg="

    static let vectors: [Vector] = [
        Vector(name: "full, https", link: "https://api.jetbox.example/connect#k=4E2BD0D4-0000-4000-8000-000000000001&m=https%3A%2F%2Fnet.jetbox.example&e=sv-demo-exit&n=Caf%C3%A9%20Home%2B1&b=100.64.0.7&s=XY_KvXXY0YNGAxTwvJ_htjoL8Cm21W32NSuBWtG_CydTZeRFNku3RjxtLw7Todmn0WcstEA1Wjru0b24cCP3AA", valid: true, messageB64: "SmV0Qm94IHNhZmV0eSB2MQpiPTEwMC42NC4wLjcKZT1zdi1kZW1vLWV4aXQKaz00RTJCRDBENC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEKbT1odHRwczovL25ldC5qZXRib3guZXhhbXBsZQpuPUNhZsOpIEhvbWUrMQo="),
        Vector(name: "same fragment via jetbox://", link: "jetbox://connect#k=4E2BD0D4-0000-4000-8000-000000000001&m=https%3A%2F%2Fnet.jetbox.example&e=sv-demo-exit&n=Caf%C3%A9%20Home%2B1&b=100.64.0.7&s=XY_KvXXY0YNGAxTwvJ_htjoL8Cm21W32NSuBWtG_CydTZeRFNku3RjxtLw7Todmn0WcstEA1Wjru0b24cCP3AA", valid: true, messageB64: nil),
        Vector(name: "any host, any server, signed", link: "https://setup.anywhere.example/connect#k=4E2BD0D4-0000-4000-8000-000000000002&m=https%3A%2F%2Fmgmt.other-server.example%3A33073&e=sv-x-exit&n=Lakeview%20Home&s=mt-qpzzT_5f_IsHNAG_1qWVxqGn_0FxVqFi6lmYHeby5P22hYuTl8jD5bH7__jg_YvewiJCeW72HAToP5aPBDg", valid: true, messageB64: "SmV0Qm94IHNhZmV0eSB2MQplPXN2LXgtZXhpdAprPTRFMkJEMEQ0LTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwMgptPWh0dHBzOi8vbWdtdC5vdGhlci1zZXJ2ZXIuZXhhbXBsZTozMzA3MwpuPUxha2V2aWV3IEhvbWUK"),
        Vector(name: "server replaced after signing", link: "https://api.jetbox.example/connect#k=4E2BD0D4-0000-4000-8000-000000000001&m=https%3A%2F%2Fevil.example&e=sv-demo-exit&n=Caf%C3%A9%20Home%2B1&b=100.64.0.7&s=XY_KvXXY0YNGAxTwvJ_htjoL8Cm21W32NSuBWtG_CydTZeRFNku3RjxtLw7Todmn0WcstEA1Wjru0b24cCP3AA", valid: false, messageB64: nil),
        Vector(name: "box ip replaced", link: "https://api.jetbox.example/connect#k=4E2BD0D4-0000-4000-8000-000000000001&m=https%3A%2F%2Fnet.jetbox.example&e=sv-demo-exit&n=Caf%C3%A9%20Home%2B1&b=100.64.0.9&s=XY_KvXXY0YNGAxTwvJ_htjoL8Cm21W32NSuBWtG_CydTZeRFNku3RjxtLw7Todmn0WcstEA1Wjru0b24cCP3AA", valid: false, messageB64: nil),
        Vector(name: "param appended after signing", link: "https://api.jetbox.example/connect#k=4E2BD0D4-0000-4000-8000-000000000001&m=https%3A%2F%2Fnet.jetbox.example&e=sv-demo-exit&n=Caf%C3%A9%20Home%2B1&b=100.64.0.7&s=XY_KvXXY0YNGAxTwvJ_htjoL8Cm21W32NSuBWtG_CydTZeRFNku3RjxtLw7Todmn0WcstEA1Wjru0b24cCP3AA&x=0", valid: false, messageB64: nil),
        Vector(name: "signed by unknown key", link: "https://api.jetbox.example/connect#k=4E2BD0D4-0000-4000-8000-000000000001&m=https%3A%2F%2Fnet.jetbox.example&e=sv-demo-exit&s=tkS4D_FtOePBgVbfJ_tPmzFx-IaEXPiTYxnCGRAIIV2jb5M4vRm46LMD3cNjikRfIGK0nsMD3j_ODonFzJ8qBQ", valid: false, messageB64: nil),
        Vector(name: "no signature", link: "https://api.jetbox.example/connect#k=4E2BD0D4-0000-4000-8000-000000000001&m=https%3A%2F%2Fnet.jetbox.example&e=sv-demo-exit", valid: false, messageB64: nil),
        Vector(name: "duplicate s", link: "https://api.jetbox.example/connect#k=4E2BD0D4-0000-4000-8000-000000000001&m=https%3A%2F%2Fnet.jetbox.example&e=sv-demo-exit&n=Caf%C3%A9%20Home%2B1&b=100.64.0.7&s=XY_KvXXY0YNGAxTwvJ_htjoL8Cm21W32NSuBWtG_CydTZeRFNku3RjxtLw7Todmn0WcstEA1Wjru0b24cCP3AA&s=AAAA", valid: false, messageB64: nil),
    ]

    override func setUp() { JBSign.trustTestKey() }
    override func tearDown() { JBSign.forgetTestKey() }

    private func fragment(_ link: String) -> String {
        URLComponents(string: link)!.percentEncodedFragment!
    }

    func testTestKeyIsTheVectorsKey() {
        XCTAssertEqual(JBSign.testPublicKeyB64, Self.testPublicKeyB64)
    }

    func testVectorsGiveTheSameValid() {
        for v in Self.vectors {
            XCTAssertEqual(JetBoxLinkSignature.isValid(fragment: fragment(v.link)), v.valid, v.name)
            print("JetBox safety vector: \(v.name) -> valid=\(JetBoxLinkSignature.isValid(fragment: fragment(v.link)))")
        }
    }

    func testVectorMessagesMatchByteForByte() {
        for v in Self.vectors {
            guard let expected = v.messageB64 else { continue }
            XCTAssertEqual(JetBoxLinkSignature.signedMessage(fragment: fragment(v.link))?.message,
                           Data(base64Encoded: expected), v.name)
        }
    }

    func testWithoutTestKeyVectorsAreNotValid() {
        JBSign.forgetTestKey()
        for v in Self.vectors {
            XCTAssertFalse(JetBoxLinkSignature.isValid(fragment: fragment(v.link)), v.name)
        }
    }

    func testProductionKeysAreThePublishedOnes() {
        XCTAssertEqual(JetBoxLinkSignature.publicKeys, [
            "prLMY2riAVq0e1nuydlSO3FOFedlsNvxjKXsHUl8/Tg=",
            "Lr8e8586oEZnBZqS678ipTemL050ha5OUIG6mqGyLu0=",
        ])
        for key in JetBoxLinkSignature.publicKeys {
            XCTAssertNotNil(try? Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: key)!))
        }
    }

    func testDuplicateNameInAnyCaseIsInvalid() {
        let link = JBSign.sign("jetbox://connect#k=4E2BD0D4-0000-4000-8000-000000000001&e=x")
        XCTAssertTrue(JetBoxLinkSignature.isValid(fragment: fragment(link)))
        XCTAssertFalse(JetBoxLinkSignature.isValid(fragment: fragment(link + "&E=y")))
        XCTAssertFalse(JetBoxLinkSignature.isValid(fragment: fragment(link + "&e=x")))
    }

    func testBadSignatureEncodingIsInvalid() {
        let base = "k=4E2BD0D4-0000-4000-8000-000000000001&e=x&s="
        XCTAssertNil(JetBoxLinkSignature.signedMessage(fragment: base + "AAAA"))
        XCTAssertNil(JetBoxLinkSignature.signedMessage(fragment: base + String(repeating: "A", count: 85) + "="))
        XCTAssertNil(JetBoxLinkSignature.signedMessage(fragment: base))
        XCTAssertNil(JetBoxLinkSignature.signedMessage(fragment: "k=1&noequals&s=" + String(repeating: "A", count: 86)))
    }

    #if JETBOX_US
    /// Сборка США: ссылка извне — только с верной подписью; хост и сервер любые.
    func testUSBuildRejectsUnsignedAndAcceptsSignedFromAnyHost() {
        for v in Self.vectors {
            let outcome = JetBoxLink.parse(URL(string: v.link)!)
            if v.valid {
                guard case .payload = outcome else { return XCTFail("\(v.name): \(outcome)") }
            } else {
                XCTAssertEqual(outcome, .unsigned, v.name)
            }
        }
        guard case .payload(let p) = JetBoxLink.parse(URL(string: Self.vectors[0].link)!) else { return XCTFail() }
        XCTAssertEqual(p.boxIP, "100.64.0.7")
        XCTAssertEqual(p.boxName, "Café Home+1")
        XCTAssertEqual(p.managementURL, "https://net.jetbox.example")
    }

    /// Ссылка из ответа verify (вход по email) — по TLS, подпись не нужна.
    func testTrustedSourceSkipsSignature() {
        let link = URL(string: "jetbox://connect#k=4E2BD0D4-0000-4000-8000-000000000001&m=https%3A%2F%2Fnet.jetbox.example&e=x")!
        XCTAssertEqual(JetBoxLink.parse(link), .unsigned)
        guard case .payload = JetBoxLink.parse(link, rules: .current.trustingSource) else { return XCTFail() }
    }

    @MainActor
    func testUnsignedLinkFailsBeforeConfirmScreen() {
        let onboarding = JetBoxOnboarding()
        onboarding.needsDataConsent = { false }
        XCTAssertTrue(onboarding.handle(URL(string: Self.vectors[3].link)!))
        XCTAssertEqual(onboarding.step, .failed(.notFromJetBox))
        XCTAssertEqual(JetBoxFailure.notFromJetBox.title, JBText.errUnsignedTitle)
        XCTAssertFalse(JetBoxFailure.notFromJetBox.isRetryable)
    }
    #else
    /// Русская сборка не меняется: подпись не требуется.
    func testRussianBuildDoesNotRequireSignature() {
        XCTAssertFalse(JetBoxLinkRules.current.requiresSignature)
    }
    #endif
}
