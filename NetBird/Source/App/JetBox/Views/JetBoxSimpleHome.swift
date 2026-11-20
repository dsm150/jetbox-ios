//
//  JetBoxSimpleHome.swift
//  JetBox
//
//  Главный экран стиля «простое»: шестерёнка справа вверху, большой круг по
//  центру (нажатие подключает и отключает), внизу одна свёрнутая строка
//  «Подробности подключения». Данные и действия те же, что у «техно»
//  (`JetBoxHomeLayout`). Выбора выхода в «простом» нет (замечание Алексея
//  21.11.2026: «только один по умолчанию») — он остаётся в «техно».
//

import SwiftUI

#if os(iOS)

struct JetBoxSimpleHomeLayout: View {
    let phase: JetBoxShieldPhase
    let statusText: String
    let box: JetBoxBox?
    let stats: JetBoxLiveStats.Snapshot?
    let connectedSince: Date?
    let power: JetBoxPowerAction
    var startsExpanded = false
    let onPower: () -> Void
    let onSettings: () -> Void

    @State private var expanded = false

    var body: some View {
        ZStack {
            JBSimple.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Spacer(minLength: 8)

                JBSimpleCircle(phase: phase,
                               accessibilityLabel: circleLabel,
                               action: power == .none ? nil : { press() })
                    .padding(.bottom, 14)

                status

                Spacer(minLength: 16)

                bottom
                    .frame(maxWidth: 420)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
        }
        .environment(\.colorScheme, .light)
        .onAppear { expanded = startsExpanded }
    }

    private var header: some View {
        HStack {
            JetBoxLogo(markHeight: 34)
            Spacer()
            JBSimpleIconButton(systemName: "gearshape.fill", label: JBText.settingsTitle, action: onSettings)
        }
        .padding(.top, 8)
    }

    private var status: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                if phase == .on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(JBSimple.accent))
                }
                Text(statusText)
                    .font(JBSimple.font(30, .black))
                    .foregroundColor(phase == .on ? JBSimple.accent : JBSimple.ink)
                    .multilineTextAlignment(.center)
            }
            if phase == .on {
                JBSimpleTrafficLine()
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(JBSimple.secondary)
                    .foregroundColor(JBSimple.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: phase)
    }

    private var subtitle: String {
        switch phase {
        case .off: return box == nil ? "" : JBText.simpleTapToConnect
        case .working: return JBText.simpleWait
        case .on: return box?.displayName ?? ""
        case .offline: return JBText.simpleOfflineHint
        }
    }

    @ViewBuilder
    private var bottom: some View {
        if box == nil {
            VStack(spacing: 8) {
                Text(JBText.homeNoBoxTitle)
                    .font(JBSimple.font(22, .black))
                    .foregroundColor(JBSimple.ink)
                Text(JBText.homeNoBoxBody)
                    .font(JBSimple.secondary)
                    .foregroundColor(JBSimple.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(22)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(JBSimple.card))
        } else if phase == .on || phase == .offline {
            details
        } else {
            // Место под подробности держим, чтобы круг не прыгал.
            Color.clear.frame(height: 52)
        }
    }

    /// Одна сворачиваемая карточка: заголовок-пилюля, в раскрытом виде —
    /// одна строка «12:38 в сети · 24 мс · напрямую» (замечание Алексея
    /// 21.11.2026: «здесь должна быть одна строка, сворачиваемая»).
    private var details: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { expanded.toggle() }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(JBText.simpleDetails)
                        .font(JBSimple.font(19, .heavy))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .heavy))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundColor(JBSimple.muted)
                if expanded {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(summaryLine(at: context.date))
                            .font(JBSimple.font(19, .bold).monospacedDigit())
                            .foregroundColor(JBSimple.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, expanded ? 14 : 0)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(JBSimple.card))
        }
        .buttonStyle(JBSimplePressStyle())
        .accessibilityHint(JBText.simpleDetails)
    }

    private func summaryLine(at now: Date) -> String {
        var parts = ["\(uptimeText(at: now)) \(JBText.dockUptime)"]
        if let ms = stats?.latencyMs { parts.append(JBText.milliseconds(ms)) }
        if stats != nil { parts.append(routeText.lowercased()) }
        return parts.joined(separator: " · ")
    }

    private func uptimeText(at now: Date) -> String {
        guard let connectedSince else { return "—" }
        return JetBoxLiveStats.uptime(Int(now.timeIntervalSince(connectedSince)))
    }

    private var routeText: String {
        guard let stats else { return "—" }
        return stats.relayed ? JBText.dockRelayed : JBText.dockDirect
    }

    private var circleLabel: String {
        switch power {
        case .connect: return JBText.homeConnect
        case .disconnect: return JBText.homeDisconnect
        case .none: return statusText
        }
    }

    private func press() {
        JBHaptics.tap()
        onPower()
    }
}

#endif
