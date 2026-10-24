//
//  JetBoxShield.swift
//  JetBox
//
//  Щит главного экрана — он же кнопка. Вариант А «Спокойный» (утверждён
//  владельцем 24.10.2026): приглашающее дыхание кольца, хвост по кругу на
//  подключении, при успехе — зелёное стекло, подскок щита, одна волна,
//  затем ровное зелёное дыхание. «Уменьшение движения» — только смена цвета.
//

import SwiftUI

#if os(iOS)

struct JetBoxShield: View {
    let phase: JetBoxShieldPhase
    var diameter: CGFloat = 188
    /// Метка для VoiceOver; без действия щит — просто индикатор.
    var accessibilityLabel: String = ""
    /// Экран по ссылке показывает щит сразу в «Под защитой» — там успех
    /// празднуется при появлении. На главном экране — нет: он открывается
    /// уже подключённым каждый день.
    var celebratesOnAppear = false
    var action: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previous: JetBoxShieldPhase?
    @State private var pop: CGFloat = 1
    @State private var waveScale: CGFloat = 1
    @State private var waveOpacity: Double = 0

    var body: some View {
        Group {
            if let action {
                Button(action: action) { face }
                    .buttonStyle(ShieldPressStyle(reduceMotion: reduceMotion))
                    .accessibilityLabel(accessibilityLabel)
            } else {
                face
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel)
            }
        }
        .onAppear {
            previous = phase
            if celebratesOnAppear && phase == .on { celebrate() }
        }
        .onChange(of: phase) { new in
            if new == .on, previous != .on { celebrate() }
            previous = new
        }
    }

    // MARK: - Слои

    private var face: some View {
        ZStack {
            decorations
            disc
            symbol
                .font(.system(size: diameter * 0.40, weight: .regular))
                .scaleEffect(pop)
                .id(phase.symbol)
                .transition(.opacity.combined(with: .scale(scale: 0.88)))
            Circle()
                .stroke(JBColor.accent, lineWidth: 2)
                .frame(width: diameter, height: diameter)
                .scaleEffect(waveScale)
                .opacity(waveOpacity)
                .allowsHitTesting(false)
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeInOut(duration: 0.35), value: phase)
        .contentShape(Circle())
    }

    /// Под защитой — сплошной фирменный синий щит с белой галочкой: на
    /// тонированном стекле иерархическая заливка сливалась с фоном.
    @ViewBuilder
    private var symbol: some View {
        if phase == .on {
            Image(systemName: phase.symbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, phase.tint)
        } else {
            Image(systemName: phase.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(phase.tint)
        }
    }

    @ViewBuilder
    private var disc: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .frame(width: diameter, height: diameter)
                .glassEffect(.regular.tint(discTint).interactive(), in: .circle)
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(discTint))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                .frame(width: diameter, height: diameter)
        }
    }

    private var discTint: Color {
        switch phase {
        case .off: return JBColor.muted.opacity(0.10)
        case .working: return phase.tint.opacity(0.16)
        case .on: return phase.tint.opacity(0.30)
        case .offline: return phase.tint.opacity(0.24)
        }
    }

    /// Кольца вокруг диска. Время берём у TimelineView — анимация не зависит
    /// от перерисовок и не накапливает состояние.
    @ViewBuilder
    private var decorations: some View {
        if reduceMotion {
            EmptyView()
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !needsTicks)) { context in
                ring(at: context.date.timeIntervalSinceReferenceDate)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func ring(at t: TimeInterval) -> some View {
        switch phase {
        case .off where action != nil:
            let b = breath(t, period: 2.8)
            Circle()
                .strokeBorder(JBColor.accent.opacity(0.45), lineWidth: 2)
                .frame(width: diameter + 28, height: diameter + 28)
                .scaleEffect(0.94 + 0.06 * b)
                .opacity(b)
        case .working(let reverse):
            let period = reverse ? 1.4 : 1.1
            let turns = t.truncatingRemainder(dividingBy: period) / period
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [JBColor.accent.opacity(0), JBColor.accent]),
                                    center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(100.8)),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: diameter + 20, height: diameter + 20)
                .rotationEffect(.degrees((reverse ? -1 : 1) * turns * 360))
        case .on:
            let b = breath(t, period: 4)
            Circle()
                .fill(RadialGradient(gradient: Gradient(colors: [JBColor.accent.opacity(0.40), JBColor.accent.opacity(0)]),
                                     center: .center,
                                     startRadius: diameter * 0.35, endRadius: diameter * 0.78))
                .frame(width: diameter * 1.6, height: diameter * 1.6)
                .scaleEffect(0.96 + 0.08 * b)
                .opacity(0.45 + 0.55 * b)
        default:
            EmptyView()
        }
    }

    private var needsTicks: Bool {
        switch phase {
        case .off: return action != nil
        case .working, .on: return true
        case .offline: return false
        }
    }

    /// 0…1 по синусоиде с заданным периодом.
    private func breath(_ t: TimeInterval, period: Double) -> Double {
        (sin(t * 2 * .pi / period) + 1) / 2
    }

    // MARK: - Момент успеха

    private func celebrate() {
        JBHaptics.success()
        guard !reduceMotion else { return }
        pop = 0.6
        withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { pop = 1 }
        waveScale = 1
        waveOpacity = 0.8
        withAnimation(.easeOut(duration: 1.1)) {
            waveScale = 1.55
            waveOpacity = 0
        }
    }
}

private struct ShieldPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#endif
