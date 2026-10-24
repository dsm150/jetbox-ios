//
//  JetBoxHomeView.swift
//  JetBox
//
//  Главный экран простого режима: щит-кнопка, состояние защиты и стеклянная
//  панель дома — в языке Liquid Glass. Апстримовые вкладки
//  (Peers, Resources, Settings) сюда не приходят — они живут в расширенном
//  режиме, который открывается семью нажатиями по версии в настройках.
//

import SwiftUI

#if os(iOS)

struct JetBoxHomeView: View {
    @EnvironmentObject var viewModel: ViewModel
    /// Вложенный ObservableObject сам по себе перерисовку не вызывает —
    /// наблюдаем за списком маршрутов явно, как это делает апстрим
    /// в ExitNodeSelectorCard.
    @ObservedObject var routes: RoutesViewModel
    @ObservedObject private var stats = JetBoxLiveStats.shared
    @State private var showsSettings = false
    @State private var showsDetails = false

    private var box: JetBoxBox? { JetBoxStore.currentBox }

    var body: some View {
        #if DEBUG
        if JetBoxShieldDemo.isRequested {
            JetBoxShieldDemoView(routes: routes)
        } else {
            live
        }
        #else
        live
        #endif
    }

    private var live: some View {
        let state = viewModel.vpnDisplayState
        let power = JetBoxPowerAction.action(for: state, hasBox: box != nil)
        return JetBoxHomeLayout(
            phase: JetBoxShieldPhase(state: state, isInternetConnected: viewModel.isInternetConnected),
            statusText: Self.statusText(for: state, online: viewModel.isInternetConnected),
            box: box,
            stats: stats.box,
            connectedSince: stats.connectedSince,
            power: power,
            onPower: { perform(power) },
            onSettings: { showsSettings = true },
            onOpenDetails: { showsDetails = true }
        )
        .sheet(isPresented: $showsSettings) {
            JetBoxSettingsView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showsDetails) {
            if let box {
                JetBoxConnectionSheet(routes: routes, stats: stats, box: box,
                                      isConnected: viewModel.vpnDisplayState == .connected)
            }
        }
        .onChange(of: viewModel.vpnDisplayState) { state in
            // Разрешение на уведомления — когда защита впервые включилась,
            // а не при запуске: тогда понятно, о чём будут уведомления.
            if state == .connected { JetBoxNotifications.requestIfNeeded() }
        }
    }

    private func perform(_ action: JetBoxPowerAction) {
        switch action {
        case .connect: viewModel.connect()
        case .disconnect: viewModel.close()
        case .none: break
        }
    }

    static func statusText(for state: VPNDisplayState, online: Bool) -> String {
        switch state {
        case .connected: return online ? JBText.homeConnected : JBText.homeOffline
        case .connecting: return JBText.homeConnecting
        case .disconnecting: return JBText.homeDisconnecting
        case .disconnected: return JBText.homeDisconnected
        }
    }
}

/// Главный экран без привязки к данным: всё приходит параметрами.
/// Так его можно показать и с настоящим туннелем, и в DEBUG-демо.
/// Включает и выключает только щит; внизу — стеклянная панель дома.
struct JetBoxHomeLayout: View {
    let phase: JetBoxShieldPhase
    let statusText: String
    let box: JetBoxBox?
    let stats: JetBoxLiveStats.Snapshot?
    let connectedSince: Date?
    let power: JetBoxPowerAction
    let onPower: () -> Void
    let onSettings: () -> Void
    let onOpenDetails: () -> Void

    var body: some View {
        ZStack {
            JetBoxBackdrop(phase: phase)

            VStack(spacing: 0) {
                header

                Spacer(minLength: 12)

                JetBoxShield(
                    phase: phase,
                    accessibilityLabel: shieldLabel,
                    action: power == .none ? nil : { press() }
                )
                .padding(.bottom, 26)

                Text(statusText)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(phase == .on ? JBColor.accent : JBColor.text)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.3), value: phase)

                Spacer(minLength: 24)

                Group {
                    if let box {
                        JetBoxHomeDock(phase: phase, box: box, stats: stats,
                                       connectedSince: connectedSince, onOpen: onOpenDetails)
                    } else {
                        JetBoxNoBoxDock()
                    }
                }
                .frame(maxWidth: 420)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 20)
        }
    }

    private func press() {
        JBHaptics.tap()
        onPower()
    }

    private var shieldLabel: String {
        switch power {
        case .connect: return JBText.homeConnect
        case .disconnect: return JBText.homeDisconnect
        case .none: return statusText
        }
    }

    private var header: some View {
        HStack {
            JetBoxLogo(markHeight: 34)
            Spacer()
            JBGlassIconButton(systemName: "gearshape", label: JBText.settingsTitle, action: onSettings)
        }
        .padding(.top, 8)
        .padding(.horizontal, 4)
    }
}

#if DEBUG
/// Только для съёмки в симуляторе: туннель там не поднимается, поэтому
/// фазы отыгрываются таймером. Аргумент запуска `-JetBoxShieldDemo`;
/// `-JetBoxShieldDemoState connecting|connected|disconnecting` — начать с
/// нужной фазы (нажатие в симуляторе идёт секунды, фаза успевает пройти).
/// В релизную сборку не попадает.
enum JetBoxShieldDemo {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-JetBoxShieldDemo")
    }

    static var initialState: VPNDisplayState {
        switch UserDefaults.standard.string(forKey: "JetBoxShieldDemoState") {
        case "connecting": return .connecting
        case "connected": return .connected
        case "disconnecting": return .disconnecting
        default: return .disconnected
        }
    }
}

struct JetBoxShieldDemoView: View {
    @ObservedObject var routes: RoutesViewModel
    @State private var state: VPNDisplayState = JetBoxShieldDemo.initialState
    @State private var since = Date().addingTimeInterval(-754)
    @State private var showsDetails = false

    private let box = JetBoxBox(managementURL: "https://netbird.jet-net.net",
                                exitNodeName: "home-ivanov",
                                selectedExitNode: nil,
                                boxName: "Дом на Озёрной",
                                registeredAt: Date())

    /// Примерные показатели — только для демо.
    private let sample = JetBoxLiveStats.Snapshot(latencyMs: 24, relayed: false,
                                                  bytesRx: 48_200_000, bytesTx: 6_100_000)

    var body: some View {
        let power = JetBoxPowerAction.action(for: state, hasBox: true)
        JetBoxHomeLayout(
            phase: JetBoxShieldPhase(state: state, isInternetConnected: true),
            statusText: JetBoxHomeView.statusText(for: state, online: true),
            box: box,
            stats: state == .connected ? sample : nil,
            connectedSince: state == .connected ? since : nil,
            power: power,
            onPower: { run(power) },
            onSettings: {},
            onOpenDetails: { showsDetails = true }
        )
        .sheet(isPresented: $showsDetails) {
            JetBoxConnectionSheet(routes: routes, stats: JetBoxLiveStats.shared, box: box,
                                  isConnected: state == .connected,
                                  demo: sample, demoSince: since)
        }
        .onAppear {
            // Запуск сразу в «Подключаем…» доигрывает переход в успех сам —
            // так видео снимается без медленных нажатий симулятора.
            if state == .connecting {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { connected() }
            }
            if UserDefaults.standard.bool(forKey: "JetBoxShieldDemoDetails") { showsDetails = true }
        }
    }

    private func connected() {
        since = Date()
        state = .connected
    }

    private func run(_ action: JetBoxPowerAction) {
        switch action {
        case .connect:
            state = .connecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { connected() }
        case .disconnect:
            state = .disconnecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { state = .disconnected }
        case .none:
            break
        }
    }
}
#endif

// MARK: - Смена выхода из простого режима

struct JetBoxExitSheet: View {
    @ObservedObject var routes: RoutesViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if routes.exitNodes.isEmpty {
                    Text(JBText.exitPickerEmpty)
                        .font(.subheadline)
                        .foregroundColor(JBColor.muted)
                } else {
                    ForEach(routes.exitNodes) { node in
                        Button {
                            routes.setExitNode(node)
                            JetBoxStore.rememberExitNode(node.name)
                            dismiss()
                        } label: {
                            HStack {
                                Text(node.name)
                                    .foregroundColor(JBColor.text)
                                Spacer()
                                if node.selected {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(JBColor.accent)
                                }
                            }
                        }
                    }
                    Button {
                        routes.setExitNode(nil)
                        JetBoxStore.rememberExitNode(nil)
                        dismiss()
                    } label: {
                        Text(JBText.homeExitNone)
                            .foregroundColor(JBColor.muted)
                    }
                }
            }
            .navigationTitle(JBText.exitPickerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(JBText.close) { dismiss() }
                }
            }
            .onAppear { routes.getRoutes() }
        }
    }
}

#endif
