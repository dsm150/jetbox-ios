//
//  JetBoxHomeDock.swift
//  JetBox
//
//  Стеклянная панель дома внизу главного экрана — вместо карточки и нижней
//  кнопки (включает и выключает теперь только щит). Вариант А прототипа,
//  утверждён владельцем 24.10.2026 «без текста-инструкции»: имя дома,
//  состояние и под защитой — три живых показателя. Нажатие — подробности.
//

import SwiftUI

#if os(iOS)

struct JetBoxHomeDock: View {
    let phase: JetBoxShieldPhase
    let box: JetBoxBox
    let stats: JetBoxLiveStats.Snapshot?
    let connectedSince: Date?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                head
                if phase == .on || phase == .offline {
                    metrics
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .jbGlassPanel(cornerRadius: 28)
        .animation(.easeInOut(duration: 0.35), value: phase)
    }

    private var head: some View {
        HStack(spacing: 12) {
            Image(systemName: "house.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                Text(box.displayName)
                    .font(.headline)
                    .foregroundColor(JBColor.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(JBColor.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(JBColor.muted)
        }
        .animation(.easeInOut(duration: 0.4), value: phase)
    }

    private var metrics: some View {
        HStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                metric(uptimeText(at: context.date), JBText.dockUptime)
            }
            metric(stats?.latencyMs.map(JBText.milliseconds) ?? "—", JBText.dockLatency)
            metric(routeText, JBText.dockRoute)
        }
    }

    private func metric(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundColor(JBColor.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(caption)
                .font(.caption2)
                .foregroundColor(JBColor.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func uptimeText(at now: Date) -> String {
        guard let connectedSince else { return "—" }
        return JetBoxLiveStats.uptime(Int(now.timeIntervalSince(connectedSince)))
    }

    private var routeText: String {
        guard let stats else { return "—" }
        return stats.relayed ? JBText.dockRelayed : JBText.dockDirect
    }

    private var subtitle: String {
        switch phase {
        case .on: return JBText.dockOn
        case .working(let reverse): return reverse ? JBText.homeDisconnecting : JBText.dockConnecting
        case .off: return JBText.dockOff
        case .offline: return JBText.dockOffline
        }
    }

    private var tint: Color {
        switch phase {
        case .on: return JBColor.ok
        case .offline: return JBColor.warn
        case .off, .working: return JBColor.accent
        }
    }
}

/// Панель без JetBox: единственный путь дальше — ссылка из письма.
struct JetBoxNoBoxDock: View {
    var body: some View {
        VStack(spacing: 6) {
            Text(JBText.homeNoBoxTitle)
                .font(.headline)
                .foregroundColor(JBColor.text)
            Text(JBText.homeNoBoxBody)
                .font(.subheadline)
                .foregroundColor(JBColor.muted)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .jbGlassPanel(cornerRadius: 28)
    }
}

extension View {
    /// Стеклянная подложка панели: на iOS 26 — стекло Apple, ниже — материал.
    @ViewBuilder
    func jbGlassPanel(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(JBColor.line.opacity(0.8), lineWidth: 1))
        }
    }
}

#endif
