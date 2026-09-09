//
//  JetBoxAdvancedAccess.swift
//  JetBox
//
//  Доступ к расширенным настройкам — по образцу «Для разработчиков» в Android:
//  семь быстрых нажатий по строке версии, с обратным отсчётом начиная
//  с четвёртого. Обычный клиент туда случайно не попадает, а поддержка
//  открывает экраны по телефону за пять секунд.
//
//  Два состояния, а не одно:
//   * «открыто» (unlocked) — в настройках виден пункт «Расширенные настройки»;
//   * «включено» (on) — приложение показывает служебные экраны NetBird.
//  Выключение закрывает оба: как в Android, чтобы вернуться, нужны новые
//  семь нажатий.
//

import Foundation

/// Счётчик нажатий по строке версии. Чистый тип без UI и без хранилища —
/// логика «семи нажатий» должна проверяться тестами, а не руками на телефоне.
struct AdvancedUnlockCounter {

    /// Столько нажатий открывает расширенные настройки.
    static let tapsRequired = 7
    /// После какого нажатия начинается обратный отсчёт (то есть подсказка
    /// впервые появляется на четвёртом).
    static let hintAfterTaps = 3
    /// Пауза, после которой счёт начинается заново: нажатия должны идти
    /// подряд, иначе случайные тычки по экрану сложатся в семь. Счёт и так
    /// обнуляется при уходе с экрана, поэтому окно человеческое — три секунды:
    /// семь раз подряд попасть в одну строку небыстро, если делать это
    /// впервые и по телефону с поддержкой.
    static let resetInterval: TimeInterval = 3

    /// Что показать клиенту после очередного нажатия.
    enum Outcome: Equatable {
        /// Ничего: первые нажатия молчат, как и в Android.
        case silent
        /// «Ещё N нажатий…»
        case hint(remaining: Int)
        /// Открыли.
        case unlocked
        /// Уже открыто — считать нечего.
        case alreadyUnlocked
    }

    private(set) var taps = 0
    private var lastTapAt: Date?

    mutating func tap(at now: Date = Date(), isUnlocked: Bool) -> Outcome {
        if isUnlocked {
            reset()
            return .alreadyUnlocked
        }
        if let lastTapAt, now.timeIntervalSince(lastTapAt) > Self.resetInterval {
            taps = 0
        }
        lastTapAt = now
        taps += 1

        if taps >= Self.tapsRequired {
            reset()
            return .unlocked
        }
        if taps > Self.hintAfterTaps {
            return .hint(remaining: Self.tapsRequired - taps)
        }
        return .silent
    }

    mutating func reset() {
        taps = 0
        lastTapAt = nil
    }
}

/// Где живёт состояние доступа. App Group, а не `UserDefaults.standard`:
/// значение переживает перезапуск и видно всем таргетам одинаково — там же
/// лежат остальные общие ключи (`GlobalConstants`).
enum JetBoxAdvancedAccess {

    /// Виден ли пункт «Расширенные настройки».
    static let unlockedKey = "jetbox.advancedUnlocked"
    /// Показываются ли служебные экраны NetBird.
    static let modeKey = JetBoxStore.advancedModeKey

    static var defaults: UserDefaults {
        UserDefaults(suiteName: GlobalConstants.userPreferencesSuiteName) ?? .standard
    }

    static var isUnlocked: Bool {
        get { defaults.bool(forKey: unlockedKey) }
        set { defaults.set(newValue, forKey: unlockedKey) }
    }

    static var isOn: Bool {
        get { defaults.bool(forKey: modeKey) }
        set { defaults.set(newValue, forKey: modeKey) }
    }

    /// Открыть доступ (семь нажатий сделаны). Сами служебные экраны при этом
    /// ещё не показываются — их включает отдельный пункт.
    static func unlock() {
        isUnlocked = true
    }

    /// Выключение: закрывает и режим, и доступ. Чтобы вернуться, нужны новые семь
    /// нажатий — иначе «выключил и снова случайно нажал» возвращает клиента
    /// туда же, откуда его и уводили.
    static func lock() {
        isOn = false
        isUnlocked = false
    }

    /// До 09.09.2026 флаг лежал в `UserDefaults.standard` и включался тумблером.
    /// Чистим его при старте: иначе на телефоне, где режим был включён, он
    /// останется включённым и в обход семи нажатий.
    static func migrateLegacyFlagIfNeeded() {
        let legacy = UserDefaults.standard
        guard legacy.object(forKey: modeKey) != nil else { return }
        legacy.removeObject(forKey: modeKey)
    }
}
