//
//  JetBoxPowerAction.swift
//  JetBox
//
//  Что делает нажатие на главном экране и как выглядит щит. Чистая логика
//  без SwiftUI-видов — покрыта JetBoxPowerActionTests.
//

import SwiftUI

/// Нажатие на щит и на нижнюю кнопку — одно и то же действие.
enum JetBoxPowerAction: Equatable {
    case connect
    case disconnect
    case none

    static func action(for state: VPNDisplayState, hasBox: Bool) -> JetBoxPowerAction {
        guard hasBox else { return .none }
        switch state {
        case .disconnected: return .connect
        case .connected: return .disconnect
        case .connecting, .disconnecting: return .none
        }
    }
}

/// Фаза щита. Не совпадает с VPNDisplayState: «нет интернета» — своя фаза,
/// а экран по ссылке ставит щит в работу на своих шагах.
enum JetBoxShieldPhase: Equatable {
    case off
    case working(reverse: Bool)
    case on
    case offline

    init(state: VPNDisplayState, isInternetConnected: Bool) {
        switch state {
        case .disconnected: self = .off
        case .connecting: self = .working(reverse: false)
        case .disconnecting: self = .working(reverse: true)
        case .connected: self = isInternetConnected ? .on : .offline
        }
    }

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    var symbol: String {
        switch self {
        case .off: return "shield.slash"
        case .working: return "shield.lefthalf.filled"
        case .on: return "checkmark.shield.fill"
        case .offline: return "exclamationmark.shield.fill"
        }
    }

    #if os(iOS)
    var tint: Color {
        switch self {
        case .off: return JBColor.muted
        case .working: return JBColor.accent
        // Под защитой — фирменный синий, не зелёный (решение владельца 24.10.2026).
        case .on: return JBColor.accent
        case .offline: return JBColor.warn
        }
    }
    #endif
}
