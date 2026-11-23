//
//  JetBoxStyle.swift
//  JetBox
//
//  Стиль оформления: «техно» (Liquid Glass, синий щит — вид до 20.11.2026)
//  и «простое» (белый фон, большой круг, фиолетовый акцент — макет Алексея
//  20.11.2026). Меняется только вид: подключение, замена подключения, выходы
//  и виджет работают одинаково в обоих стилях.
//
//  Хранится в App Group: стиль нужен и виджету.
//

#if os(iOS)
import Foundation
import WidgetKit

enum JetBoxStyle: String, CaseIterable, Identifiable {
    case simple
    case techno

    var id: String { rawValue }

    static let key = "jetbox.style"
    /// Сборка США: по умолчанию — «простое» (Алексей, 21.11.2026), только на
    /// время выпуска; стиль, который человек уже выбрал сам, не перетирается.
    /// Русская сборка: только «техно», «простого» в ней нет (владелец, 23.11.2026).
    #if JETBOX_US
    static let fallback: JetBoxStyle = .simple
    #else
    static let fallback: JetBoxStyle = .techno
    #endif

    /// Есть ли выбор стиля в этой сборке.
    #if JETBOX_US
    static let isSelectable = true
    #else
    static let isSelectable = false
    #endif

    static var defaults: UserDefaults { JetBoxAdvancedAccess.defaults }

    static var current: JetBoxStyle { current(in: defaults) }

    /// Первый запуск (ключа нет) — «простое»; выбранное раньше «техно» остаётся.
    static func current(in defaults: UserDefaults) -> JetBoxStyle {
        resolve(defaults.string(forKey: key))
    }

    /// Сохранённое значение → стиль сборки. В русской сборке всегда «техно»,
    /// даже если в App Group осталось «simple» от прежней версии.
    static func resolve(_ raw: String?) -> JetBoxStyle {
        guard isSelectable else { return .techno }
        return JetBoxStyle(rawValue: raw ?? "") ?? fallback
    }

    var title: String {
        switch self {
        case .simple: return JBText.styleSimple
        case .techno: return JBText.styleTechno
        }
    }

    /// Виджет перечитывает стиль только при новой временной шкале.
    static func styleDidChange() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    #if DEBUG
    /// Для съёмки в симуляторе: `-JetBoxStyle simple|techno` в аргументах запуска.
    /// `-JetBoxWidgetDemo connected|disconnected` — состояние для виджета
    /// (в симуляторе туннеля нет, виджет берёт последнее сохранённое).
    static func applyLaunchOverride() {
        if let status = UserDefaults.standard.string(forKey: "JetBoxWidgetDemo") {
            defaults.set(status, forKey: "netbird.widget.vpnStatus")
        }
        if isSelectable, let raw = UserDefaults.standard.string(forKey: "JetBoxStyle"),
           let style = JetBoxStyle(rawValue: raw) {
            defaults.set(style.rawValue, forKey: key)
        }
        styleDidChange()
    }
    #endif
}

#endif
