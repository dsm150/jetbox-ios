//
//  JetBoxSimpleHome.swift
//  JetBox
//
//  Главный экран стиля «простое»: шестерёнка справа вверху, большой круг по
//  центру (нажатие подключает и отключает), внизу свёрнутые «Подробности
//  подключения». Данные и действия те же, что у «техно» (`JetBoxHomeLayout`).
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
    /// Имя текущего выхода и признак «выходов больше одного» — тогда в
    /// подробностях есть строка выбора выхода (как в листе «техно»).
    let exitName: String?
    let showsExit: Bool
    var startsExpanded = false
    let onPower: () -> Void
    let onSettings: () -> Void
    let onExit: () -> Void

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

    private var details: some View {
        VStack(spacing: 12) {
            if expanded {
                HStack(spacing: 8) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        chip(uptimeText(at: context.date), JBText.dockUptime)
                    }
                    chip(stats?.latencyMs.map(JBText.milliseconds) ?? "—", JBText.dockLatency)
                    chip(routeText, JBText.dockRoute)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))

                if showsExit {
                    Button(action: onExit) {
                        JBSimpleRow(title: JBText.settingsExit, value: exitName ?? JBText.homeExitNone, chevron: true)
                            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(JBSimple.card))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.3)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(JBText.simpleDetails)
                        .font(JBSimple.font(19, .heavy))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .heavy))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundColor(JBSimple.muted)
                .padding(.horizontal, 24)
                .frame(minHeight: 52)
                .background(Capsule().fill(JBSimple.card))
            }
            .buttonStyle(JBSimplePressStyle())
        }
    }

    private func chip(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(JBSimple.font(21, .heavy).monospacedDigit())
                .foregroundColor(JBSimple.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(caption)
                .font(JBSimple.font(17, .semibold))
                .foregroundColor(JBSimple.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(JBSimple.card))
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

// MARK: - Выбор выхода

/// Список выходов в стиле «простое». Данные приходят параметрами, чтобы тот
/// же вид работал и с настоящими маршрутами, и в демо.
struct JetBoxSimpleExitList: View {
    let options: [String]
    let selected: String?
    let onSelect: (String?) -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                JBSimpleHeader(title: JBText.exitPickerTitle, trailingTitle: JBText.close, onTrailing: onClose)
                    .padding(.bottom, 6)

                if options.isEmpty {
                    Text(JBText.exitPickerEmpty)
                        .font(JBSimple.secondary)
                        .foregroundColor(JBSimple.muted)
                } else {
                    Text(JBText.exitPickerMessage)
                        .font(JBSimple.secondary)
                        .foregroundColor(JBSimple.muted)
                        .padding(.bottom, 4)
                    ForEach(options, id: \.self) { name in
                        option(name, isSelected: name == selected) { onSelect(name) }
                    }
                    JBSimpleTextButton(JBText.homeExitNone, color: JBSimple.muted) { onSelect(nil) }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .background(JBSimple.background.ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }

    private func option(_ name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                JBSimpleIconTile(systemName: "house.fill", size: 48,
                                 tint: isSelected ? .white : JBSimple.accent,
                                 fill: isSelected ? JBSimple.accent : JBSimple.accentTint)
                Text(name)
                    .font(JBSimple.font(20, .bold))
                    .foregroundColor(JBSimple.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(JBSimple.accent)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 76)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(JBSimple.card))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isSelected ? JBSimple.accent : Color.clear, lineWidth: 2))
        }
        .buttonStyle(JBSimplePressStyle())
    }
}

/// Выбор выхода с главного экрана: те же действия, что у `JetBoxExitSheet`.
struct JetBoxSimpleExitSheet: View {
    @ObservedObject var routes: RoutesViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        JetBoxSimpleExitList(
            options: routes.exitNodes.map(\.name),
            selected: routes.selectedExitNode?.name,
            onSelect: { name in
                let node = name.flatMap { n in routes.exitNodes.first { $0.name == n } }
                routes.setExitNode(node)
                JetBoxStore.rememberExitNode(node?.name)
                dismiss()
            },
            onClose: { dismiss() }
        )
        .onAppear { routes.getRoutes() }
    }
}

#endif
