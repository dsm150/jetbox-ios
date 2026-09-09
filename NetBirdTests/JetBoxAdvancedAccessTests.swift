//
//  JetBoxAdvancedAccessTests.swift
//  NetBirdTests
//
//  «Семь нажатий» и хранение состояния доступа к расширенным настройкам.
//  Цена ошибки в счётчике — обычный клиент проваливается в служебные экраны
//  NetBird и пишет в поддержку; цена ошибки в хранении — режим переживает
//  выключение и возвращается сам.
//

import XCTest
@testable import NetBird

final class AdvancedUnlockCounterTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// Быстрая серия нажатий: каждое на 0,3 с позже предыдущего.
    private func fastTaps(_ count: Int,
                          from counter: AdvancedUnlockCounter = AdvancedUnlockCounter(),
                          isUnlocked: Bool = false) -> (AdvancedUnlockCounter, [AdvancedUnlockCounter.Outcome]) {
        var c = counter
        var out: [AdvancedUnlockCounter.Outcome] = []
        for i in 0..<count {
            out.append(c.tap(at: t0.addingTimeInterval(Double(i) * 0.3), isUnlocked: isUnlocked))
        }
        return (c, out)
    }

    func testFirstThreeTapsAreSilent() {
        let (_, out) = fastTaps(3)
        XCTAssertEqual(out, [.silent, .silent, .silent])
    }

    func testCountdownStartsOnFourthTap() {
        let (_, out) = fastTaps(6)
        XCTAssertEqual(out.suffix(3), [.hint(remaining: 3), .hint(remaining: 2), .hint(remaining: 1)])
    }

    func testSeventhTapUnlocks() {
        let (_, out) = fastTaps(7)
        XCTAssertEqual(out.last, .unlocked)
        XCTAssertEqual(out.filter { $0 == .unlocked }.count, 1)
    }

    func testCounterResetsAfterUnlock() {
        // После открытия счёт начинается с нуля: следующее нажатие — не восьмое.
        var (c, _) = fastTaps(7)
        XCTAssertEqual(c.taps, 0)
        XCTAssertEqual(c.tap(at: t0.addingTimeInterval(10), isUnlocked: false), .silent)
    }

    func testPauseResetsTheCount() {
        var c = AdvancedUnlockCounter()
        for i in 0..<6 {
            _ = c.tap(at: t0.addingTimeInterval(Double(i) * 0.3), isUnlocked: false)
        }
        // Пауза больше resetInterval — считаем заново, седьмое нажатие
        // после паузы уже не открывает.
        let after = c.tap(at: t0.addingTimeInterval(60), isUnlocked: false)
        XCTAssertEqual(after, .silent)
        XCTAssertEqual(c.taps, 1)
    }

    func testTapsExactlyAtResetIntervalStillCount() {
        var c = AdvancedUnlockCounter()
        var last: AdvancedUnlockCounter.Outcome = .silent
        for i in 0..<7 {
            last = c.tap(at: t0.addingTimeInterval(Double(i) * AdvancedUnlockCounter.resetInterval),
                         isUnlocked: false)
        }
        XCTAssertEqual(last, .unlocked)
    }

    func testAlreadyUnlockedIsReportedAndCountsNothing() {
        var c = AdvancedUnlockCounter()
        XCTAssertEqual(c.tap(at: t0, isUnlocked: true), .alreadyUnlocked)
        XCTAssertEqual(c.taps, 0)
    }
}

final class JetBoxAdvancedAccessStorageTests: XCTestCase {

    private var savedUnlocked = false
    private var savedOn = false

    override func setUp() {
        super.setUp()
        savedUnlocked = JetBoxAdvancedAccess.isUnlocked
        savedOn = JetBoxAdvancedAccess.isOn
        JetBoxAdvancedAccess.lock()
    }

    override func tearDown() {
        JetBoxAdvancedAccess.isUnlocked = savedUnlocked
        JetBoxAdvancedAccess.isOn = savedOn
        UserDefaults.standard.removeObject(forKey: JetBoxAdvancedAccess.modeKey)
        super.tearDown()
    }

    func testDefaultIsLocked() {
        XCTAssertFalse(JetBoxAdvancedAccess.isUnlocked)
        XCTAssertFalse(JetBoxAdvancedAccess.isOn)
    }

    func testStateLivesInAppGroupNotStandardDefaults() {
        // Хранилище — App Group: значение видно всем таргетам и переживает
        // перезапуск. В UserDefaults.standard не должно попадать ничего.
        JetBoxAdvancedAccess.unlock()
        JetBoxAdvancedAccess.isOn = true

        let group = UserDefaults(suiteName: GlobalConstants.userPreferencesSuiteName)
        XCTAssertEqual(group?.bool(forKey: JetBoxAdvancedAccess.unlockedKey), true)
        XCTAssertEqual(group?.bool(forKey: JetBoxAdvancedAccess.modeKey), true)
        XCTAssertNil(UserDefaults.standard.object(forKey: JetBoxAdvancedAccess.unlockedKey))
    }

    func testUnlockDoesNotTurnTheModeOn() {
        // Семь нажатий только показывают пункт меню; служебные экраны
        // включает уже сам клиент отдельным нажатием.
        JetBoxAdvancedAccess.unlock()
        XCTAssertTrue(JetBoxAdvancedAccess.isUnlocked)
        XCTAssertFalse(JetBoxAdvancedAccess.isOn)
    }

    func testLockClosesBothModeAndAccess() {
        JetBoxAdvancedAccess.unlock()
        JetBoxAdvancedAccess.isOn = true

        JetBoxAdvancedAccess.lock()

        XCTAssertFalse(JetBoxAdvancedAccess.isOn)
        XCTAssertFalse(JetBoxAdvancedAccess.isUnlocked, "после выключения пункт должен исчезнуть — иначе туда возвращаются одним нажатием")
    }

    func testLegacyStandardFlagIsCleared() {
        // На телефонах со сборкой до 09.09.2026 флаг лежал в standard и
        // включался тумблером. Если его не убрать, режим останется включённым
        // в обход семи нажатий.
        UserDefaults.standard.set(true, forKey: JetBoxAdvancedAccess.modeKey)

        JetBoxAdvancedAccess.migrateLegacyFlagIfNeeded()

        XCTAssertNil(UserDefaults.standard.object(forKey: JetBoxAdvancedAccess.modeKey))
        XCTAssertFalse(JetBoxAdvancedAccess.isOn)
    }
}
