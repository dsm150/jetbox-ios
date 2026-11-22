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
                               "protection off", "protection is off",
                               // Российский контекст не для американского пользователя (21.11.2026).
                               "roskomnadzor", "rkn", "restricted site", "russia"]

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

    /// Русские тексты проверяются по исходному каталогу: в сборке США
    /// (JETBOX_HOME_ONLY=YES) ru.lproj нет, а каталог должен оставаться
    /// полным и чистым для русской сборки.
    private func sourceCatalog() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NetBird/Source/App/JetBox/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try XCTUnwrap(json?["strings"] as? [String: Any])
    }

    private func russianValues() throws -> [String: String] {
        var result: [String: String] = [:]
        for (key, entry) in try sourceCatalog() {
            let ru = ((entry as? [String: Any])?["localizations"] as? [String: Any])?["ru"] as? [String: Any]
            if let unit = ru?["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
                result[key] = value
            } else if let plural = (ru?["variations"] as? [String: Any])?["plural"] as? [String: Any] {
                result[key] = plural.values.compactMap { (($0 as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String }
                    .joined(separator: " | ")
            }
        }
        return result
    }

    func testRussianStringsAvoidForbiddenWords() throws {
        for (key, value) in try russianValues() where key.hasPrefix("jetbox.") {
            for word in forbiddenRU {
                XCTAssertFalse(value.lowercased().contains(word), "«\(word)» в русской строке \(key): \(value)")
            }
        }
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

    func testEnglishIsDevelopmentLanguage() {
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
    }

    /// Русский каталог полон — для русской сборки (JETBOX_HOME_ONLY=NO).
    func testRussianCatalogIsComplete() throws {
        let en = try strings("en"), ru = try russianValues()
        let missing = Set(en.keys.filter { $0.hasPrefix("jetbox.") }).subtracting(ru.keys)
        XCTAssertTrue(missing.isEmpty, "нет русского перевода: \(missing.sorted())")
    }

    /// Решение владельца 21.11.2026: сборка США — только английский на любом
    /// iPhone (ru.lproj убирает шаг сборки), русская сборка — с русским.
    func testRussianShippedOnlyInRussianBuild() throws {
        let widget = try XCTUnwrap(widgetBundle, "виджет не найден в PlugIns")
        for (name, bundle) in [("приложение", Bundle.main), ("виджет", widget)] {
            let ru = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: "ru.lproj")
            if JetBoxEdition.homeOnly {
                XCTAssertNil(ru, "\(name): ru.lproj в сборке США")
                XCTAssertFalse(bundle.localizations.contains("ru"), "\(name): ru среди локализаций сборки США")
                XCTAssertEqual(Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: ["ru-RU"]).first, "en",
                               "\(name): русский iPhone должен получить английский")
            } else {
                XCTAssertNotNil(ru, "\(name): нет ru.lproj в русской сборке")
            }
        }
    }

    func testEnglishStringsAvoidForbiddenWords() throws {
        try assertNoForbiddenWords("en", forbiddenEN)
    }

    /// «Protected» в английском — только когда весь интернет идёт через свою
    /// коробку (решение руководителя 22.11.2026, 1.0 (14)): тогда это правда.
    func testProtectedOnlyWhenAllInternetGoesThroughOwnBox() throws {
        let allowed: Set<String> = ["jetbox.home.connected_all", "jetbox.protected.title_all"]
        for (key, value) in try strings("en") where key.hasPrefix("jetbox.") && value.lowercased().contains("protect") {
            XCTAssertTrue(allowed.contains(key), "«protect» вне состояния «весь интернет через JetBox»: \(key): \(value)")
        }
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
        XCTAssertEqual(en["jetbox.ready.hint"], "One tap and your phone joins your home network.")
        XCTAssertEqual(en["jetbox.home.connected"], "On your home network")
        XCTAssertEqual(en["jetbox.home.disconnected"], "Not on your home network")
    }

    func testCopyrightHolderFollowsEdition() throws {
        // Решение Алексея 21.11.2026: в американской сборке правообладатель —
        // INSTASHOP Corporation, в русской — JetNet, как было.
        let en = try strings("en")
        let us = try XCTUnwrap(en[JetBoxEdition.aboutLegalKey(homeOnly: true)])
        XCTAssertTrue(us.contains("INSTASHOP Corporation"), us)
        XCTAssertFalse(us.contains("JetNet"), us)
        let ru = try XCTUnwrap(en[JetBoxEdition.aboutLegalKey(homeOnly: false)])
        XCTAssertTrue(ru.contains("JetNet"), ru)
        XCTAssertEqual(JetBoxEdition.copyrightHolder(homeOnly: true), "INSTASHOP Corporation")
        XCTAssertEqual(JetBoxEdition.copyrightHolder(homeOnly: false), "JetNet")
    }
}
