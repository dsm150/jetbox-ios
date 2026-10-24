//
//  JetBoxConnectionSheet.swift
//  JetBox
//
//  Подробности подключения — по нажатию на стеклянную панель дома. Выбор
//  выхода здесь появляется, только если сервер отдаёт больше одного выхода:
//  у клиента один дом — и выход у него один (решение владельца 24.10.2026).
//
//  Лист по высоте содержимого (замечание владельца 25.10.2026: на половине
//  экрана под четырьмя строками оставалось много пустого места). Поэтому не
//  List в NavigationView, а своя раскладка, высота которой меряется и
//  отдаётся системе как размер листа.
//

import SwiftUI

#if os(iOS)

struct JetBoxConnectionSheet: View {
    @ObservedObject var routes: RoutesViewModel
    @ObservedObject var stats: JetBoxLiveStats
    let box: JetBoxBox
    let isConnected: Bool
    var demo: JetBoxLiveStats.Snapshot?
    var demoSince: Date?

    @Environment(\.dismiss) private var dismiss
    @State private var showsExitPicker = false
    @State private var contentHeight: CGFloat = 320

    private var snapshot: JetBoxLiveStats.Snapshot? { demo ?? stats.box }
    private var since: Date? { demoSince ?? stats.connectedSince }
    private var showsExit: Bool { isConnected && routes.exitNodes.count > 1 }

    var body: some View {
        VStack(spacing: 18) {
            header

            card {
                if isConnected {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        row(JBText.detailsUptime, uptime(at: context.date))
                    }
                    divider
                    row(JBText.detailsLatency, snapshot?.latencyMs.map(JBText.milliseconds) ?? "—")
                    divider
                    row(JBText.detailsRoute,
                        snapshot.map { $0.relayed ? JBText.detailsRelayed : JBText.dockDirect } ?? "—")
                    divider
                    row(JBText.detailsTraffic, traffic)
                } else {
                    row(JBText.detailsRoute, JBText.dockOff)
                }
            }

            if showsExit {
                card {
                    Button {
                        showsExitPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            row(JBText.settingsExit, routes.selectedExitNode?.name ?? JBText.homeExitNone)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(JBColor.muted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SheetHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(SheetHeightKey.self) { contentHeight = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .jbFittedSheet(height: contentHeight)
        .sheet(isPresented: $showsExitPicker) {
            JetBoxExitSheet(routes: routes)
        }
        .onAppear {
            if isConnected { routes.getRoutes() }
        }
    }

    // MARK: - Части

    private var header: some View {
        ZStack {
            Text(box.displayName)
                .font(.headline)
                .foregroundColor(JBColor.text)
                .lineLimit(1)
                .padding(.horizontal, 96)
            HStack {
                Spacer()
                doneButton
            }
        }
    }

    @ViewBuilder
    private var doneButton: some View {
        if #available(iOS 26.0, *) {
            Button(JBText.done) { dismiss() }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .foregroundStyle(JBColor.text)
        } else {
            Button(JBText.done) { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundColor(JBColor.accent)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundColor(JBColor.muted)
                .lineLimit(1)
            Spacer(minLength: 8)
            // Значение не ужимаем: с minimumScaleFactor короткие цифры
            // («24 мс») рисовались мельче длинного трафика.
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundColor(JBColor.text)
                .fixedSize()
        }
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Divider().overlay(JBColor.line)
    }

    // MARK: - Значения

    private func uptime(at now: Date) -> String {
        guard let since else { return "—" }
        return JetBoxLiveStats.uptime(Int(now.timeIntervalSince(since)))
    }

    private var traffic: String {
        guard let snapshot else { return "—" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return "\(f.string(fromByteCount: snapshot.bytesRx)) / \(f.string(fromByteCount: snapshot.bytesTx))"
    }
}

private struct SheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Лист ровно по содержимому, где это умеет система (iOS 16+); ниже —
    /// обычный лист.
    @ViewBuilder
    func jbFittedSheet(height: CGFloat) -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.height(max(height, 160))])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }
}

#endif
