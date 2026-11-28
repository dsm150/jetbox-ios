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
    /// Демо для съёмки: сразу открыть лист подробностей.
    var startsWithDetails = false
    /// Проба DNS (1.0 (34)): DNS идёт мимо JetBox — капсула под кругом.
    var dnsBypassed = false
    let onPower: () -> Void
    let onSettings: () -> Void

    @State private var showsDetails = false
    @State private var showsDNSFix = false

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
        .onAppear { if startsWithDetails { showsDetails = true } }
        .sheet(isPresented: $showsDetails) {
            JBSimpleInfoSheet(title: JBText.errDetails) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    JBSimpleInfoRow(title: JBText.detailsUptime, value: uptimeText(at: context.date))
                }
                JBSimpleInfoRow(title: JBText.detailsLatency, value: stats?.latencyMs.map(JBText.milliseconds) ?? "—")
                JBSimpleInfoRow(title: JBText.detailsRoute, value: routeText)
            }
        }
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
                // Длинный заголовок США «You are in your home network, protected by
                // JetBox» (1.0 (31)) переносится сам и не обрезается даже на SE.
                Text(statusText)
                    .font(JBSimple.font(statusText.count > 30 ? 26 : 30, .black))
                    .foregroundColor(phase == .on ? JBSimple.accent : JBSimple.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Бежит только пока подключаемся или ждём дом; в «Protected» —
            // сплошная и неподвижная (1.0 (24)).
            if phase == .on {
                JBSimpleTrafficLine(moving: false)
            } else if phase == .working(reverse: false) {
                JBSimpleTrafficLine(moving: true)
            }
            if !subtitle.isEmpty {
                HStack(spacing: 8) {
                    Text(subtitle)
                        .font(JBSimple.secondary)
                        .foregroundColor(JBSimple.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    // Подробности подключения — за значком (замечание Алексея
                    // 21.11.2026: под кругом ничего лишнего).
                    if box != nil && (phase == .on || phase == .offline) {
                        JBSimpleInfoButton(label: JBText.simpleDetails) { showsDetails = true }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: phase)
    }

    private var subtitle: String {
        switch phase {
        case .off: return box == nil ? "" : JBText.simpleTapToConnect
        case .working: return JBText.simpleWait
        // Выход своей коробки должен быть, а его нет в туннеле — говорим прямо.
        case .on: return box == nil ? "" : (JBText.exitWarning ?? box?.displayName ?? "")
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
        } else if dnsBypassed && phase == .on {
            Button { showsDNSFix = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(JBSimple.error)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(JBText.dnsBypassed)
                            .font(JBSimple.font(17, .bold))
                            .foregroundColor(JBSimple.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(JBText.dnsHowToFix)
                            .font(JBSimple.font(17, .heavy))
                            .foregroundColor(JBSimple.accent)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(JBSimple.card))
            }
            .buttonStyle(JBSimplePressStyle())
            .alert(JBText.dnsHowToFix, isPresented: $showsDNSFix) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(JBText.dnsFixBody)
            }
        } else {
            // Под кругом ничего нет; место держим, чтобы круг стоял ровно.
            Color.clear.frame(height: 52)
        }
    }

    private func uptimeText(at now: Date) -> String {
        guard let connectedSince else { return "—" }
        return JetBoxLiveStats.uptime(Int(now.timeIntervalSince(connectedSince)))
    }

    private var routeText: String {
        guard let stats else { return "—" }
        return JBText.route(JetBoxLiveStats.route(stats))
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
