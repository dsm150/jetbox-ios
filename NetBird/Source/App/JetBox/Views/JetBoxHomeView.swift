//
//  JetBoxHomeView.swift
//  JetBox
//
//  Главный экран простого режима: щит-кнопка, состояние защиты, JetBox,
//  выход и капсула действия — в языке Liquid Glass. Апстримовые вкладки
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
    @State private var showsSettings = false
    @State private var showsExitPicker = false

    private var box: JetBoxBox? { JetBoxStore.currentBox }

    var body: some View {
        #if DEBUG
        if JetBoxShieldDemo.isRequested {
            JetBoxShieldDemoView()
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
            exitName: currentExitName,
            canChangeExit: state == .connected,
            power: power,
            onPower: { perform(power) },
            onSettings: { showsSettings = true },
            onChangeExit: { showsExitPicker = true }
        )
        .sheet(isPresented: $showsSettings) {
            JetBoxSettingsView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showsExitPicker) {
            JetBoxExitSheet(routes: routes)
                .environmentObject(viewModel)
        }
        .onAppear {
            // Селектор выхода читается только через расширение: пока туннеля
            // нет, список пуст — это нормально, обновимся после подключения.
            if viewModel.vpnDisplayState == .connected {
                routes.getRoutes()
            }
        }
    }

    private func perform(_ action: JetBoxPowerAction) {
        switch action {
        case .connect: viewModel.connect()
        case .disconnect: viewModel.close()
        case .none: break
        }
    }

    private var currentExitName: String? {
        if let selected = routes.selectedExitNode?.name { return selected }
        return box?.effectiveExitNode
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
struct JetBoxHomeLayout: View {
    let phase: JetBoxShieldPhase
    let statusText: String
    let box: JetBoxBox?
    let exitName: String?
    let canChangeExit: Bool
    let power: JetBoxPowerAction
    let onPower: () -> Void
    let onSettings: () -> Void
    let onChangeExit: () -> Void

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
                    .foregroundColor(phase == .on ? JBColor.ok : JBColor.text)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.3), value: phase)
                    .padding(.bottom, 24)

                Group {
                    if let box { boxCard(box) } else { noBoxCard }
                }
                .frame(maxWidth: 420)

                Spacer(minLength: 16)

                if box != nil {
                    actionButton
                        .frame(maxWidth: 420)
                        .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, 24)
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
    }

    private func boxCard(_ box: JetBoxBox) -> some View {
        JBCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(JBText.settingsSectionBox)
                    .font(.footnote)
                    .foregroundColor(JBColor.muted)
                Text(box.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(JBColor.text)
                    .lineLimit(2)
                Divider().overlay(JBColor.line)
                HStack {
                    Text(exitName.map { JBText.homeExit($0) } ?? JBText.homeExitNone)
                        .font(.subheadline)
                        .foregroundColor(JBColor.muted)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if canChangeExit {
                        Button(JBText.homeChangeExit, action: onChangeExit)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(JBColor.accent)
                    }
                }
            }
        }
    }

    private var noBoxCard: some View {
        JBCard {
            VStack(spacing: 10) {
                Text(JBText.homeNoBoxTitle)
                    .font(.headline)
                    .foregroundColor(JBColor.text)
                Text(JBText.homeNoBoxBody)
                    .font(.subheadline)
                    .foregroundColor(JBColor.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch power {
        case .connect:
            JBGlassButton(JBText.homeConnect) { press() }
        case .disconnect:
            JBGlassButton(JBText.homeDisconnect, role: .secondary) { press() }
        case .none:
            JBGlassButton(statusText, role: .secondary) {}
                .disabled(true)
                .opacity(0.6)
        }
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
    @State private var state: VPNDisplayState = JetBoxShieldDemo.initialState

    private let box = JetBoxBox(managementURL: "https://netbird.jet-net.net",
                                exitNodeName: "home-ivanov",
                                selectedExitNode: nil,
                                boxName: "Дом на Озёрной",
                                registeredAt: Date())

    var body: some View {
        let power = JetBoxPowerAction.action(for: state, hasBox: true)
        JetBoxHomeLayout(
            phase: JetBoxShieldPhase(state: state, isInternetConnected: true),
            statusText: JetBoxHomeView.statusText(for: state, online: true),
            box: box,
            exitName: box.effectiveExitNode,
            canChangeExit: state == .connected,
            power: power,
            onPower: { run(power) },
            onSettings: {},
            onChangeExit: {}
        )
        .onAppear {
            // Запуск сразу в «Подключаем…» доигрывает переход в успех сам —
            // так видео снимается без медленных нажатий симулятора.
            if state == .connecting {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { state = .connected }
            }
        }
    }

    private func run(_ action: JetBoxPowerAction) {
        switch action {
        case .connect:
            state = .connecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { state = .connected }
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
