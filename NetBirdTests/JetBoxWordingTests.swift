//
//  JetBoxWordingTests.swift
//  NetBirdTests
//
//  Правило владельца: в текстах, которые видит клиент, нет слова «коробка»
//  (только JetBox, объект, устройство) и нет лексики «обход блокировок».
//  Правило нарушалось дважды вручную, поэтому проверяется сборкой:
//  тест читает скомпилированные каталоги строк приложения — и русский,
//  и английский — и смотрит на значения, а не на ключи.
//

import XCTest
@testable import NetBird

final class JetBoxWordingTests: XCTestCase {

    /// Слова, которых в клиентских строках быть не должно.
    /// Ключи (`jetbox.settings.section.box`) не в счёт — их клиент не видит.
    private let forbiddenRU = ["коробк", "обход", "заблокирован"]
    private let forbiddenEN = ["bypass", "blocked", "censorship"]

    private func strings(_ language: String) throws -> [String: String] {
        let bundle = Bundle(for: JetBoxWordingTests.self)
        // Тесты хостятся приложением, поэтому каталог лежит либо в бандле
        // тестов, либо в бандле приложения.
        let candidates = [bundle, Bundle.main].compactMap {
            $0.url(forResource: "Localizable", withExtension: "strings", subdirectory: "\(language).lproj")
        }
        let url = try XCTUnwrap(candidates.first, "не найден \(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: String])
    }

    private func assertNoForbiddenWords(_ language: String, _ words: [String]) throws {
        let table = try strings(language)
        XCTAssertGreaterThan(table.count, 30, "каталог \(language) подозрительно мал")

        for (key, value) in table where key.hasPrefix("jetbox.") {
            for word in words {
                XCTAssertFalse(value.lowercased().contains(word),
                               "«\(word)» в клиентской строке \(key): \(value)")
            }
        }
    }

    func testRussianStringsAvoidForbiddenWords() throws {
        try assertNoForbiddenWords("ru", forbiddenRU)
    }

    func testEnglishStringsAvoidForbiddenWords() throws {
        try assertNoForbiddenWords("en", forbiddenEN)
    }

    func testEnglishStringsDoNotCallItABox() throws {
        // «box» отдельным словом — тот же запрет, что и «коробка»; при этом
        // «JetBox» и «no_box» в ключах трогать нельзя.
        let table = try strings("en")
        let pattern = try NSRegularExpression(pattern: "\\bboxe?s?\\b", options: [.caseInsensitive])
        for (key, value) in table where key.hasPrefix("jetbox.") {
            let range = NSRange(value.startIndex..., in: value)
            XCTAssertNil(pattern.firstMatch(in: value, range: range),
                         "«box» отдельным словом в \(key): \(value)")
        }
    }

    func testConnectScreenPromisesTheHomeNetwork() throws {
        // Легенда продукта — доступ к своей сети, а не «весь трафик через
        // коробку»: описание в магазине и текст на экране должны совпадать.
        let ru = try strings("ru")["jetbox.ready.hint"]
        XCTAssertEqual(ru, "Одно нажатие — и телефон окажется в вашей домашней сети.")
    }
}
