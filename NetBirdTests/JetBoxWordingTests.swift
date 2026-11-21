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
    /// С 21.11.2026 приложение только на английском (релиз в США); к прежним
    /// словам добавлены запреты из правил копирайта Алексея.
    private let forbiddenEN = ["bypass", "blocked", "censorship", "vpn", "anonym",
                               "change location", "unblock", "protection on",
                               "protection off", "protection is off"]

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

    // MARK: - Английская локаль (21.11.2026, сборка для США)
    //
    // Язык — по языку устройства: английский iPhone видит всё по-английски,
    // русский — по-русски. Английский — язык разработки (запасной для всех
    // остальных языков), поэтому кириллицы в en быть не должно нигде:
    // ни в приложении, ни в виджете.

    private let cyrillic = try! NSRegularExpression(pattern: "[А-Яа-яЁё]")

    private func table(_ bundle: Bundle, _ language: String, _ name: String = "Localizable") -> [String: String]? {
        guard let url = bundle.url(forResource: name, withExtension: "strings", subdirectory: "\(language).lproj"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return nil }
        return plist as? [String: String]
    }

    private var widgetBundle: Bundle? {
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)
        else { return nil }
        return items.first { $0.lastPathComponent.hasPrefix("NetBirdWidget") }.flatMap(Bundle.init(url:))
    }

    private func assertNoCyrillic(_ table: [String: String], _ what: String) {
        for (key, value) in table {
            let range = NSRange(value.startIndex..., in: value)
            XCTAssertNil(cyrillic.firstMatch(in: value, range: range), "\(what): непереведено «\(key)» = \(value)")
        }
    }

    func testEnglishAppStringsHaveNoCyrillic() throws {
        let en = try strings("en")
        assertNoCyrillic(en, "приложение en")
    }

    func testEnglishWidgetStringsHaveNoCyrillic() throws {
        let widget = try XCTUnwrap(widgetBundle, "виджет не найден в PlugIns")
        let en = try XCTUnwrap(table(widget, "en"), "нет en.lproj/Localizable.strings у виджета")
        XCTAssertGreaterThan(en.count, 20)
        assertNoCyrillic(en, "виджет en")
    }

    func testEnglishIsDevelopmentLanguageAndRussianShipped() throws {
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
        XCTAssertTrue(Bundle.main.localizations.contains("ru"), "русский должен остаться для русских телефонов")
        let en = try strings("en"), ru = try strings("ru")
        let missing = Set(en.keys.filter { $0.hasPrefix("jetbox.") }).subtracting(ru.keys)
        XCTAssertTrue(missing.isEmpty, "нет русского перевода: \(missing.sorted())")
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
        let en = try strings("en")
        XCTAssertEqual(en["jetbox.ready.hint"], "One tap and the phone joins your home network.")
        XCTAssertEqual(en["jetbox.home.connected"], "In home network")
        XCTAssertEqual(en["jetbox.home.disconnected"], "Not in home network")
    }
}
