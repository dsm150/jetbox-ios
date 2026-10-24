//
//  JetBoxBackdrop.swift
//  JetBox
//
//  Фон под стеклом: три мягких пятна фирменного цвета медленно дрейфуют.
//  Стеклу Apple нужно, что преломлять — на ровном фоне оно выглядит серым.
//  Под защитой пятна насыщаются фирменным синим. Радиальный градиент вместо blur:
//  тот же вид без постоянной нагрузки на GPU.
//

import SwiftUI

#if os(iOS)

struct JetBoxBackdrop: View {
    let phase: JetBoxShieldPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { context in
            blobs(at: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.2), value: phase)
        .accessibilityHidden(true)
    }

    private func blobs(at t: TimeInterval) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                JBColor.background
                blob(primary, size: w * 1.25)
                    .position(x: w * (0.22 + 0.06 * sin(t / 7)), y: h * (0.26 + 0.04 * cos(t / 9)))
                blob(secondary, size: w * 1.05)
                    .position(x: w * (0.82 + 0.05 * cos(t / 8)), y: h * (0.46 + 0.05 * sin(t / 6)))
                blob(primary, size: w * 0.95)
                    .position(x: w * (0.45 + 0.07 * sin(t / 11)), y: h * (0.92 + 0.03 * cos(t / 7)))
            }
        }
    }

    private var strength: Double { scheme == .dark ? 0.34 : 0.24 }

    /// Только фирменные цвета: синий насыщается от «выключено» к «под
    /// защитой» (зелёный убран по решению владельца 24.10.2026).
    private var primary: Color {
        switch phase {
        case .off: return JBColor.accent.opacity(strength * 0.6)
        case .working: return JBColor.accent.opacity(strength)
        case .on: return JBColor.accent.opacity(min(strength * 1.45, 0.5))
        case .offline: return JBColor.warn.opacity(strength * 0.8)
        }
    }

    /// Второй тон — голубее фирменного синего, чтобы фон не был плоским.
    private var secondary: Color {
        switch phase {
        case .offline: return JBColor.warn.opacity(strength * 0.5)
        case .off: return Color(red: 0.36, green: 0.76, blue: 1.0).opacity(strength * 0.5)
        case .working: return Color(red: 0.36, green: 0.76, blue: 1.0).opacity(strength * 0.8)
        case .on: return Color(red: 0.36, green: 0.76, blue: 1.0).opacity(strength * 1.2)
        }
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(gradient: Gradient(colors: [color, color.opacity(0)]),
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
    }
}

#endif
