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
    /// По умолчанию — «простое» (Алексей, 21.11.2026). Стиль, который
    /// человек уже выбрал сам, хранится и не перетирается.
    static let fallback: JetBoxStyle = .simple

    static var defaults: UserDefaults { JetBoxAdvancedAccess.defaults }

    static var current: JetBoxStyle { current(in: defaults) }

    /// Первый запуск (ключа нет) — «простое»; выбранное раньше «техно» остаётся.
    static func current(in defaults: UserDefaults) -> JetBoxStyle {
        JetBoxStyle(rawValue: defaults.string(forKey: key) ?? "") ?? fallback
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
        if let raw = UserDefaults.standard.string(forKey: "JetBoxStyle"),
           let style = JetBoxStyle(rawValue: raw) {
            defaults.set(style.rawValue, forKey: key)
        }
        styleDidChange()
    }
    #endif
}

#endif
