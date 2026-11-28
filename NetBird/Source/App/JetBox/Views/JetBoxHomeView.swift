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
    /// «Подключено» — когда отвечает дом, а не просто поднят туннель (1.0 (14)).
    @ObservedObject private var readiness = JetBoxHomeReadiness.shared
    @State private var showsSettings = false
    @State private var showsDetails = false
    @StateObject private var login = JetBoxLoginModel()
    /// Согласие «какие данные собираем» (сборка США) — до входа и подключения.
    @State private var consentAccepted = JetBoxDataConsent.isAccepted
    @AppStorage(JetBoxStyle.key, store: JetBoxStyle.defaults)
    private var styleRaw = JetBoxStyle.fallback.rawValue
    @EnvironmentObject private var jetbox: JetBoxOnboarding

    /// Пока идёт подключение по ссылке (сборка США) — коробка из ссылки:
    /// при первом входе записи ещё нет, при замене в ней ещё прежняя.
    private var box: JetBoxBox? { jetbox.connectingBox ?? JetBoxStore.currentBox }
    /// Сборка США без подключения: вместо пустого состояния — вход по email.
    private var showsEmailLogin: Bool {
        #if DEBUG && JETBOX_US
        if JetBoxLoginModel.demoRequested { return true }
        #endif
        return JetBoxEdition.showsEmailLogin(box: box)
    }
    /// Русская сборка: всегда false — «простого» там нет (JetBoxStyle.resolve).
    private var isSimple: Bool { JetBoxStyle.resolve(styleRaw) == .simple }
    private var needsConsent: Bool {
        #if DEBUG
        // Съёмка демо-экранов в симуляторе: `-JetBoxSkipConsent YES`.
        if UserDefaults.standard.bool(forKey: "JetBoxSkipConsent") { return false }
        #endif
        return JetBoxDataConsent.needsConsent(accepted: consentAccepted)
    }

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

    @ViewBuilder
    private func layout(power: JetBoxPowerAction, state: VPNDisplayState) -> some View {
        let phase = JetBoxShieldPhase(state: state, isInternetConnected: viewModel.isInternetConnected)
        let status = Self.statusText(for: state, online: viewModel.isInternetConnected)
        if isSimple {
            #if JETBOX_US
            JetBoxSimpleHomeLayout(
                phase: phase,
                statusText: status,
                box: box,
                stats: stats.box,
                connectedSince: stats.connectedSince,
                power: power,
                dnsBypassed: stats.dnsVerdict == .bypassed,
                onPower: { perform(power) },
                onSettings: { showsSettings = true }
            )
            #endif
        } else {
            JetBoxHomeLayout(
                phase: phase,
                statusText: status,
                box: box,
                stats: stats.box,
                connectedSince: stats.connectedSince,
                power: power,
                dnsBypassed: stats.dnsVerdict == .bypassed,
                onPower: { perform(power) },
                onSettings: { showsSettings = true },
                onOpenDetails: { showsDetails = true }
            )
        }
    }

    private var live: some View {
        // Подключение по ссылке без экрана сценария (сборка США, 26): до самого
        // «Protected» главный экран показывает «Connecting…», щит не нажимается —
        // сценарий сам регистрирует устройство, поднимает туннель и ждёт дом.
        let byLink = jetbox.isConnectingInBackground
        let state = byLink ? .connecting : readiness.displayState(viewModel.vpnDisplayState)
        // Пока ждём дом, выключить можно: кнопка — по настоящему состоянию туннеля.
        let power = byLink ? JetBoxPowerAction.none : JetBoxPowerAction.action(for: viewModel.vpnDisplayState, hasBox: box != nil)
        return Group {
            // Согласие и вход по email — только в сборке США (в русской оба
            // условия ложны, а экраны на наборе «простого» не собираются).
            if needsConsent {
                #if JETBOX_US
                JetBoxDataConsentView {
                    JetBoxDataConsent.accept()
                    consentAccepted = true
                    jetbox.resumeAfterDataConsent()
                }
                #endif
            } else if showsEmailLogin {
                #if JETBOX_US
                JetBoxEmailLoginView(model: login, onSettings: { showsSettings = true })
                    // Код подтверждён — дальше обычный сценарий ссылки /connect.
                    .onAppear { login.onConnect = { [weak jetbox = jetbox] url in jetbox?.handle(url, trusted: true) } }
                #endif
            } else {
                layout(power: power, state: state)
            }
        }
        .sheet(isPresented: $showsSettings) {
            if isSimple {
                #if JETBOX_US
                JetBoxSimpleSettingsView()
                    .environmentObject(viewModel)
                    .environmentObject(jetbox)
                #endif
            } else {
                JetBoxSettingsView()
                    .environmentObject(viewModel)
                    .environmentObject(jetbox)
            }
        }
        .onChange(of: jetbox.signOutCount) { _ in
            // После выхода — чистая форма входа, как у свежей установки.
            showsDetails = false
            login.reset()
            if let notice = jetbox.takeLoginNotice() { login.showNotice(notice) }
        }
        .sheet(isPresented: $showsDetails) {
            if let box {
                JetBoxConnectionSheet(routes: routes, stats: stats, box: box,
                                      isConnected: viewModel.vpnDisplayState == .connected)
            }
        }
        .onChange(of: viewModel.vpnDisplayState) { state in
            readiness.tunnelStateChanged(state, viewModel: viewModel)
            // Разрешение на уведомления — когда защита впервые включилась,
            // а не при запуске: тогда понятно, о чём будут уведомления.
            if state == .connected { JetBoxNotifications.requestIfNeeded() }
            // «Только дом»: чужой выход снимаем, свой при включённом тумблере включаем.
            if state == .connected { Task { await JetBoxHomeOnlyGuard.enforce(routes: routes) } }
        }
        .onAppear {
            readiness.tunnelStateChanged(viewModel.vpnDisplayState, viewModel: viewModel)
            if viewModel.vpnDisplayState == .connected {
                Task { await JetBoxHomeOnlyGuard.enforce(routes: routes) }
            }
        }
        #if DEBUG
        .onAppear {
            jetbox.showDemoIfRequested()
            login.applyDemoIfRequested()
        }
        #endif
    }

    private func perform(_ action: JetBoxPowerAction) {
        switch action {
        // Сборка США: без VPN-профиля — сначала объяснение (1.0 (32)).
        case .connect: jetbox.connectTunnel(viewModel: viewModel)
        case .disconnect: viewModel.close()
        case .none: break
        }
    }

    static func statusText(for state: VPNDisplayState, online: Bool) -> String {
        switch state {
        case .connected: return online ? JBText.homeConnectedNow : JBText.homeOffline
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
    /// Проба DNS (1.0 (34)): DNS идёт мимо JetBox — капсула над панелью дома.
    var dnsBypassed = false
    let onPower: () -> Void
    let onSettings: () -> Void
    let onOpenDetails: () -> Void

    @State private var showsDNSFix = false

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

                if dnsBypassed && phase == .on {
                    Button { showsDNSFix = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(JBColor.warn)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(JBText.dnsBypassed)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(JBColor.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(JBText.dnsHowToFix)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(JBColor.accent)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 420)
                    .padding(.bottom, 10)
                    .alert(JBText.dnsHowToFix, isPresented: $showsDNSFix) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(JBText.dnsFixBody)
                    }
                }

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
    @State private var showsSettings = false
    @EnvironmentObject private var viewModel: ViewModel
    @EnvironmentObject private var jetbox: JetBoxOnboarding
    @AppStorage(JetBoxStyle.key, store: JetBoxStyle.defaults)
    private var styleRaw = JetBoxStyle.fallback.rawValue

    /// Русская сборка: всегда false — «простого» там нет (JetBoxStyle.resolve).
    private var isSimple: Bool { JetBoxStyle.resolve(styleRaw) == .simple }
    /// `-JetBoxDemoScreen settings|about|signout|delete|details` — сразу открыть нужный лист.
    private var screen: String { UserDefaults.standard.string(forKey: "JetBoxDemoScreen") ?? "" }

    private let box = JetBoxBox(managementURL: JetBoxConfig.defaultManagementURL,
                                exitNodeName: "home-ivanov",
                                selectedExitNode: nil,
                                boxName: UserDefaults.standard.string(forKey: "JetBoxDemoBoxName") ?? "Lakeview Home",
                                registeredAt: Date())

    /// `-JetBoxDemoAllInternet YES` — «весь интернет через дом», как у живой
    /// записи США с выходом своей коробки: «Protected by your JetBox».
    private func status(_ state: VPNDisplayState) -> String {
        if state == .connected, UserDefaults.standard.bool(forKey: "JetBoxDemoAllInternet") {
            return JBText.homeConnectedAll
        }
        return JetBoxHomeView.statusText(for: state, online: true)
    }

    /// Примерные показатели — только для демо.
    /// `-JetBoxDemoRoute notDirect` — прямое соединение не вышло (сборка США без relay).
    /// `-JetBoxDemoDNS bypassed` — капсула «DNS doesn't go through JetBox» (1.0 (34)).
    private let demoDNSBypassed = UserDefaults.standard.string(forKey: "JetBoxDemoDNS") == "bypassed"

    private let sample = JetBoxLiveStats.Snapshot(
        latencyMs: 24, relayed: false, bytesRx: 48_200_000, bytesTx: 6_100_000,
        connected: UserDefaults.standard.string(forKey: "JetBoxDemoRoute") != "notDirect")

    @ViewBuilder
    private func layout(_ power: JetBoxPowerAction) -> some View {
        if isSimple {
            #if JETBOX_US
            JetBoxSimpleHomeLayout(
                phase: JetBoxShieldPhase(state: state, isInternetConnected: true),
                statusText: status(state),
                box: box,
                stats: state == .connected ? sample : nil,
                connectedSince: state == .connected ? since : nil,
                power: power,
                startsWithDetails: screen == "details",
                dnsBypassed: demoDNSBypassed,
                onPower: { run(power) },
                onSettings: { showsSettings = true }
            )
            #endif
        } else {
            JetBoxHomeLayout(
                phase: JetBoxShieldPhase(state: state, isInternetConnected: true),
                statusText: status(state),
                box: box,
                stats: state == .connected ? sample : nil,
                connectedSince: state == .connected ? since : nil,
                power: power,
                dnsBypassed: demoDNSBypassed,
                onPower: { run(power) },
                onSettings: { showsSettings = true },
                onOpenDetails: { showsDetails = true }
            )
        }
    }

    var body: some View {
        let power = JetBoxPowerAction.action(for: state, hasBox: true)
        layout(power)
        .sheet(isPresented: $showsSettings) {
            if isSimple {
                #if JETBOX_US
                JetBoxSimpleSettingsView(demoBoxName: box.displayName, opensAbout: screen == "about",
                                         opensHelp: screen == "help",
                                         asksSignOut: screen == "signout", asksDelete: screen == "delete",
                                         showsLastOwner: screen == "lastowner",
                                         showsSignOutFailed: screen == "signoutfailed")
                    .environmentObject(viewModel)
                    .environmentObject(jetbox)
                #endif
            } else if screen == "about" {
                NavigationView { JetBoxAboutView() }
            } else {
                JetBoxSettingsView().environmentObject(viewModel).environmentObject(jetbox)
            }
        }
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
            switch screen {
            case "settings", "about", "help", "signout", "delete", "lastowner", "signoutfailed": showsSettings = true
            case "details": if !isSimple { showsDetails = true }
            default: break
            }
            jetbox.showDemoIfRequested()
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
