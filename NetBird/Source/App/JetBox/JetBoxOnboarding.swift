//
//  JetBoxOnboarding.swift
//  JetBox
//
//  Сценарий «одной кнопки»: ссылка из Кабинета → регистрация по setup key →
//  туннель → выбор выхода → «вы под защитой».
//
//  Живёт на уровне приложения (@StateObject в NetBirdApp), потому что ссылка
//  может прийти раньше, чем загрузится ViewModel ядра.
//

import Foundation
import Combine
import NetworkExtension

#if os(iOS)

// MARK: - Отказы

/// Каждый отказ — это заголовок, объяснение и понятное «что делать».
/// Технический текст от ядра прячем под «Подробности»: он нужен поддержке,
/// а не клиенту.
enum JetBoxFailure: Equatable {
    case brokenLink
    case offline
    case managementUnreachable(String?)
    case keyRejected(String?)
    case tunnelFailed
    case other(String)

    var title: String {
        switch self {
        case .brokenLink: return JBText.errBrokenTitle
        case .offline: return JBText.errOfflineTitle
        case .managementUnreachable: return JBText.errUnreachableTitle
        case .keyRejected: return JBText.errKeyTitle
        case .tunnelFailed: return JBText.errTunnelTitle
        case .other: return JBText.errGenericTitle
        }
    }

    var message: String {
        switch self {
        case .brokenLink: return JBText.errBrokenBody
        case .offline: return JBText.errOfflineBody
        case .managementUnreachable: return JBText.errUnreachableBody
        case .keyRejected: return JBText.errKeyBody
        case .tunnelFailed: return JBText.errTunnelBody
        case .other: return JBText.errGenericBody
        }
    }

    /// Технические подробности для поддержки. Ключа здесь нет и быть не может:
    /// в текст ошибки ядра он не попадает.
    var details: String? {
        switch self {
        case .managementUnreachable(let d), .keyRejected(let d): return d
        case .other(let d): return d
        case .brokenLink, .offline, .tunnelFailed: return nil
        }
    }

    /// Повтор имеет смысл не всегда: испорченную ссылку повторять нечем.
    var isRetryable: Bool {
        switch self {
        case .brokenLink: return false
        default: return true
        }
    }
}

// MARK: - Сценарий

@MainActor
final class JetBoxOnboarding: ObservableObject {

    enum Step: Equatable {
        /// Экрана нет, приложение живёт обычной жизнью.
        case idle
        /// Ссылка разобрана, ждём нажатия единственной кнопки.
        case ready(JetBoxLinkPayload)
        /// Ссылка ведёт на другую коробку — спрашиваем подтверждение.
        case confirmSwitch(JetBoxLinkPayload, current: String)
        /// Регистрируем устройство по setup key.
        case registering(JetBoxLinkPayload)
        /// Поднимаем туннель.
        case connecting(JetBoxLinkPayload)
        /// Туннель есть, ищем и включаем выход в интернет.
        case selectingExit(JetBoxLinkPayload)
        /// Выход не определился сам — просим выбрать.
        case chooseExit(JetBoxLinkPayload, options: [String])
        /// Готово.
        case protected(exitNode: String?)
        case failed(JetBoxFailure)
    }

    @Published private(set) var step: Step = .idle

    /// Держим сильную ссылку: ServerViewModel живёт ровно столько, сколько
    /// длится регистрация, но убить его раньше времени нельзя — внутри
    /// висит continuation колбэка Go-SDK.
    private var registration: ServerViewModel?
    private var flowTask: Task<Void, Never>?
    /// Ссылка, по которой идёт (или шёл) сценарий. Нужна отдельно от `step`:
    /// в `.failed` шаг полезной нагрузки уже не несёт, а «Попробовать снова»
    /// обязано повторить именно её.
    private var lastPayload: JetBoxLinkPayload?

    /// Сколько ждём туннель после успешной регистрации. За это время
    /// укладывается и запрос разрешения на VPN-профиль, и холодный старт ядра.
    private let tunnelTimeout: TimeInterval = 45
    /// Сколько ждём появления маршрутов после подъёма туннеля.
    private let routesTimeout: TimeInterval = 15

    var isPresenting: Bool { step != .idle }

    // MARK: Вход по ссылке

    /// Точка входа из `onOpenURL` / `onContinueUserActivity`.
    /// Возвращает true, если ссылка наша и обработана.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        switch JetBoxLink.parse(url) {
        case .notOurs:
            return false

        case .broken:
            AppLogger.shared.log("JetBox: ссылка не проходит проверку формата, в сеть не идём")
            flowTask?.cancel()
            step = .failed(.brokenLink)
            return true

        case .payload(let payload):
            // Повторное открытие той же ссылки посреди работы сценария не
            // должно откатывать его в начало.
            if let active = activePayload, active == payload, !isRestartable {
                return true
            }
            AppLogger.shared.log("JetBox: ссылка принята, объект \(payload.displayName), ключ \(payload.maskedKey)")
            JetBoxStore.skipUpstreamOnboarding()
            flowTask?.cancel()
            lastPayload = payload

            if let box = JetBoxStore.currentBox, box.identity != payload.boxIdentity {
                step = .confirmSwitch(payload, current: box.displayName)
            } else {
                // Тот же JetBox: имя из ссылки свежее — запоминаем сразу, даже
                // если клиент нажмёт «Отмена».
                if let renamed = JetBoxStore.currentBox?.renamed(by: payload) {
                    JetBoxStore.currentBox = renamed
                }
                step = .ready(payload)
            }
            return true
        }
    }

    // MARK: Кнопки

    func connect(viewModel: ViewModel) {
        guard let payload = activePayload else { return }
        start(payload: payload, viewModel: viewModel)
    }

    func confirmSwitch(viewModel: ViewModel) {
        guard case let .confirmSwitch(payload, _) = step else { return }
        start(payload: payload, viewModel: viewModel)
    }

    func retry(viewModel: ViewModel) {
        guard let payload = lastPayload else {
            dismiss()
            return
        }
        start(payload: payload, viewModel: viewModel)
    }

    func chooseExit(_ name: String?, viewModel: ViewModel) {
        guard case .chooseExit = step else { return }
        flowTask?.cancel()
        flowTask = Task { @MainActor in
            if let name {
                await applyExitNode(named: name, viewModel: viewModel)
                JetBoxStore.rememberExitNode(name)
                step = .protected(exitNode: name)
                JetBoxNotifications.requestIfNeeded()
            } else {
                step = .protected(exitNode: nil)
                JetBoxNotifications.requestIfNeeded()
            }
        }
    }

    func dismiss() {
        flowTask?.cancel()
        flowTask = nil
        registration = nil
        lastPayload = nil
        step = .idle
    }

    // MARK: - Сценарий целиком

    private func start(payload: JetBoxLinkPayload, viewModel: ViewModel) {
        flowTask?.cancel()
        flowTask = Task { @MainActor in
            await run(payload: payload, viewModel: viewModel)
        }
    }

    private func run(payload: JetBoxLinkPayload, viewModel: ViewModel) async {
        // 1. Сеть. Без неё регистрация всё равно упадёт по таймауту — лучше
        //    сказать честно и сразу.
        guard viewModel.isInternetConnected else {
            step = .failed(.offline)
            return
        }

        // 2. Регистрация устройства по setup key.
        step = .registering(payload)
        let model = ServerViewModel(
            configurationFilePath: Preferences.configFile() ?? "",
            deviceName: Device.getName()
        )
        registration = model

        await model.loginWithSetupKey(managementServerUrl: payload.managementURL,
                                      setupKey: payload.setupKey)
        if Task.isCancelled { return }

        guard model.isOperationSuccessful else {
            step = .failed(Self.failure(from: model.viewErrors))
            registration = nil
            return
        }
        registration = nil
        JetBoxStore.remember(payload)
        AppLogger.shared.log("JetBox: устройство зарегистрировано на объекте")

        // 3. Туннель.
        step = .connecting(payload)
        viewModel.connect()

        guard await waitForTunnel(viewModel: viewModel) else {
            if Task.isCancelled { return }
            step = .failed(.tunnelFailed)
            return
        }

        // 4. Выход в интернет.
        step = .selectingExit(payload)
        switch await resolveExitNode(payload: payload, viewModel: viewModel) {
        case .selected(let name):
            JetBoxStore.rememberExitNode(name)
            step = .protected(exitNode: name)
            JetBoxNotifications.requestIfNeeded()
        case .ambiguous(let options):
            step = .chooseExit(payload, options: options)
        case .none:
            step = .protected(exitNode: nil)
            JetBoxNotifications.requestIfNeeded()
        }
    }

    /// Ждём, пока расширение доложит `.connected`. Отдельного колбэка на это
    /// в апстриме нет: состояние живёт в @Published у ViewModel и обновляется
    /// опросом расширения, поэтому здесь тоже опрос — но с честным таймаутом.
    private func waitForTunnel(viewModel: ViewModel) async -> Bool {
        let deadline = Date().addingTimeInterval(tunnelTimeout)
        while Date() < deadline {
            if Task.isCancelled { return false }
            if viewModel.vpnDisplayState == .connected { return true }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    private enum ExitOutcome {
        case selected(String)
        case ambiguous([String])
        case none
    }

    /// Выход в интернет клиент включает НЕ сам: политики на management только
    /// разрешают маршрут, а выбирает его клиент. Имя маршрута приходит в
    /// ссылке (`e=`); если его нет или он не нашёлся — работает фолбэк.
    private func resolveExitNode(payload: JetBoxLinkPayload, viewModel: ViewModel) async -> ExitOutcome {
        let routes = viewModel.routeViewModel
        let deadline = Date().addingTimeInterval(routesTimeout)
        var nodes: [RoutesSelectionInfo] = []

        while Date() < deadline {
            if Task.isCancelled { return .none }
            routes.getRoutes()
            try? await Task.sleep(nanoseconds: 900_000_000)
            nodes = routes.exitNodes
            if !nodes.isEmpty { break }
        }

        guard !nodes.isEmpty else { return .none }

        // 1. Имя из ссылки. Сравнение точное — так же, как в ядре.
        if let wanted = payload.exitNodeName,
           let match = nodes.first(where: { $0.name == wanted }) {
            await select(match, in: routes)
            return .selected(match.name)
        }

        // 2. Ровно один выход — выбираем его.
        if nodes.count == 1, let only = nodes.first {
            await select(only, in: routes)
            AppLogger.shared.log("JetBox: выход выбран автоматически — единственный доступный")
            return .selected(only.name)
        }

        // 3. Ноль или больше одного — спрашиваем человека.
        AppLogger.shared.log("JetBox: выход из ссылки не найден, показываем выбор (\(nodes.count) вариантов)")
        return .ambiguous(nodes.map(\.name))
    }

    private func applyExitNode(named name: String, viewModel: ViewModel) async {
        let routes = viewModel.routeViewModel
        guard let node = routes.exitNodes.first(where: { $0.name == name }) else { return }
        await select(node, in: routes)
    }

    private func select(_ node: RoutesSelectionInfo, in routes: RoutesViewModel) async {
        guard !node.selected else { return }
        routes.setExitNode(node)
        // Дать ядру применить маршрут до того, как экран скажет «под защитой».
        try? await Task.sleep(nanoseconds: 700_000_000)
    }

    // MARK: - Мелочи

    private var activePayload: JetBoxLinkPayload? {
        switch step {
        case .ready(let p), .confirmSwitch(let p, _), .registering(let p),
             .connecting(let p), .selectingExit(let p), .chooseExit(let p, _):
            return p
        case .idle, .protected, .failed:
            return nil
        }
    }

    /// Состояния, из которых повторный приход той же ссылки должен начать
    /// сценарий заново, а не быть проигнорированным.
    private var isRestartable: Bool {
        switch step {
        case .ready, .confirmSwitch, .failed, .idle, .protected: return true
        case .registering, .connecting, .selectingExit, .chooseExit: return false
        }
    }

    /// Перевод ошибок ядра в человеческие. Сами строки ядра английские и
    /// техничные — клиенту они уезжают только в «Подробности».
    private static func failure(from errors: ServerViewErrors) -> JetBoxFailure {
        if let key = errors.setupKeyError {
            return .keyRejected(key)
        }
        if let url = errors.urlError {
            return .managementUnreachable(url)
        }
        if let general = errors.generalError {
            let lowered = general.lowercased()
            if lowered.contains("setup key") || lowered.contains("expired") {
                return .keyRejected(general)
            }
            if lowered.contains("deadline exceeded")
                || lowered.contains("connection refused")
                || lowered.contains("no such host")
                || lowered.contains("unavailable") {
                return .managementUnreachable(general)
            }
            return .other(general)
        }
        return .other("")
    }
}

#endif
