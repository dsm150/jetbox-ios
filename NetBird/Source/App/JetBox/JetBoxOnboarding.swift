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
    case foreignServer
    case offline
    case managementUnreachable(String?)
    case keyRejected(String?)
    case tunnelFailed
    /// Ссылка входа из письма просрочена или уже использована (410).
    case loginExpired
    /// У JetBox клиента уже предельное число устройств (409 device_limit).
    case deviceLimit
    /// Кабинет ограничил частоту подтверждений (429).
    case loginRateLimited
    case other(String)

    var title: String {
        switch self {
        case .brokenLink: return JBText.errBrokenTitle
        case .foreignServer: return JBText.errForeignTitle
        case .offline: return JBText.errOfflineTitle
        case .managementUnreachable: return JBText.errUnreachableTitle
        case .keyRejected: return JBText.errKeyTitle
        case .tunnelFailed: return JBText.errTunnelTitle
        case .loginExpired: return JBText.errLoginExpiredTitle
        case .deviceLimit: return JBText.errDeviceLimitTitle
        case .loginRateLimited: return JBText.errLoginRateTitle
        case .other: return JBText.errGenericTitle
        }
    }

    var message: String {
        switch self {
        case .brokenLink: return JBText.errBrokenBody
        case .foreignServer: return JBText.errForeignBody
        case .offline: return JBText.errOfflineBody
        case .managementUnreachable: return JBText.errUnreachableBody
        case .keyRejected: return JBText.errKeyBody
        case .tunnelFailed: return JBText.errTunnelBody
        case .loginExpired: return JBText.errLoginExpiredBody
        case .deviceLimit: return JBText.errDeviceLimitBody
        case .loginRateLimited: return JBText.errLoginRateBody
        case .other: return JBText.errGenericBody
        }
    }

    /// Технические подробности для поддержки. Ключа здесь нет и быть не может:
    /// в текст ошибки ядра он не попадает.
    var details: String? {
        switch self {
        case .managementUnreachable(let d), .keyRejected(let d): return d
        case .other(let d): return d
        case .brokenLink, .foreignServer, .offline, .tunnelFailed,
             .loginExpired, .deviceLimit, .loginRateLimited: return nil
        }
    }

    /// Ссылку входа повторять бесполезно — нужна новая: вместо «Повторить»
    /// кнопка ведёт на экран email.
    var asksForNewLoginLink: Bool { self == .loginExpired }

    /// Повтор имеет смысл не всегда: испорченную ссылку повторять нечем.
    var isRetryable: Bool {
        switch self {
        case .brokenLink, .foreignServer, .loginExpired, .deviceLimit: return false
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
        /// Ссылка входа из письма: меняем токен на параметры подключения.
        case signingIn
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
    /// Токен ссылки входа, пока он не обменян: нужен «Повторить» после обрыва
    /// сети. Только в памяти, в журнал не пишется.
    private var lastLoginToken: String?
    /// API входа по email; в тестах подменяется.
    var loginAPI = JetBoxLoginAPI()

    /// Сколько ждём туннель после успешной регистрации. За это время
    /// укладывается и запрос разрешения на VPN-профиль, и холодный старт ядра.
    private let tunnelTimeout: TimeInterval = 45
    /// Сколько ждём появления маршрутов после подъёма туннеля.
    private let routesTimeout: TimeInterval = 15
    /// Сколько ждём остановки прежнего туннеля при замене подключения.
    private let stopTimeout: TimeInterval = 10

    var isPresenting: Bool { step != .idle }

    // MARK: Вход по ссылке

    /// Точка входа из `onOpenURL` / `onContinueUserActivity`.
    /// Возвращает true, если ссылка наша и обработана.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        switch JetBoxLoginLink.parse(url) {
        case .token(let token):
            if step == .signingIn, token == lastLoginToken { return true }
            AppLogger.shared.log("JetBox: ссылка входа из письма принята")
            JetBoxStore.skipUpstreamOnboarding()
            startLogin(token: token)
            return true
        case .broken:
            AppLogger.shared.log("JetBox: ссылка входа без токена или с испорченным токеном, в сеть не идём")
            flowTask?.cancel()
            lastLoginToken = nil
            step = .failed(.brokenLink)
            return true
        case .notOurs:
            break
        }

        switch JetBoxLink.parse(url) {
        case .notOurs:
            return false

        case .broken:
            AppLogger.shared.log("JetBox: ссылка не проходит проверку формата, в сеть не идём")
            flowTask?.cancel()
            step = .failed(.brokenLink)
            return true

        case .foreignServer:
            // Чужой сервер: ни вопроса, ни регистрации, текущее подключение не трогаем.
            AppLogger.shared.log("JetBox: адрес сервера в ссылке вне маски *.jet-net.net, в сеть не идём")
            flowTask?.cancel()
            step = .failed(.foreignServer)
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

            if let box = JetBoxStore.currentBox, !box.isSameConnection(as: payload) {
                step = .confirmSwitch(payload, current: box.displayName)
            } else {
                // Тот же JetBox, а имени в записи не было — запоминаем сразу,
                // даже если клиент нажмёт «Отмена».
                if let named = JetBoxStore.currentBox?.named(by: payload) {
                    JetBoxStore.currentBox = named
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
        if lastPayload == nil, let token = lastLoginToken {
            startLogin(token: token)
            return
        }
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
        lastLoginToken = nil
        step = .idle
    }

    // MARK: - Вход по ссылке из письма

    private func startLogin(token: String) {
        flowTask?.cancel()
        lastPayload = nil
        lastLoginToken = token
        step = .signingIn
        let api = loginAPI
        flowTask = Task { @MainActor in
            let outcome = await api.verify(token: token, deviceName: Device.getName())
            if Task.isCancelled { return }
            finishLogin(outcome)
        }
    }

    private func finishLogin(_ outcome: JetBoxLoginAPI.VerifyOutcome) {
        switch outcome {
        case .connect(let url):
            // Токен израсходован: дальше обычный путь ссылки /connect —
            // маска сервера, проверка ключа, «переключить?», одна кнопка.
            lastLoginToken = nil
            flowTask = nil
            if !handle(url) { step = .failed(.brokenLink) }
        case .expired:
            lastLoginToken = nil
            step = .failed(.loginExpired)
        case .deviceLimit:
            lastLoginToken = nil
            step = .failed(.deviceLimit)
        case .rateLimited:
            step = .failed(.loginRateLimited)
        case .offline:
            step = .failed(.offline)
        case .unavailable:
            step = .failed(.managementUnreachable(nil))
        }
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

        // 2. Регистрация устройства по setup key. При замене подключения —
        //    под новым ключом WireGuard, см. JetBoxIdentity.
        step = .registering(payload)
        var clock = StageClock()
        let activeConfig = Preferences.configFile() ?? ""
        let plan = JetBoxIdentity.plan(current: JetBoxStore.currentBox, payload: payload,
                                       configExists: FileManager.default.fileExists(atPath: activeConfig))
        let loginConfig = plan == .fresh ? JetBoxIdentity.stagingPath(for: activeConfig) : activeConfig
        if plan == .fresh {
            try? FileManager.default.removeItem(atPath: loginConfig)
            AppLogger.shared.log("JetBox: замена подключения — регистрируем новую личность устройства")
        }
        let model = ServerViewModel(configurationFilePath: loginConfig, deviceName: Device.getName())
        registration = model

        await model.loginWithSetupKey(managementServerUrl: payload.managementURL,
                                      setupKey: payload.setupKey)
        if Task.isCancelled {
            // Обрыв до замены конфига: действующий конфиг и туннель не тронуты.
            if plan == .fresh { try? FileManager.default.removeItem(atPath: loginConfig) }
            return
        }

        guard model.isOperationSuccessful else {
            if plan == .fresh { try? FileManager.default.removeItem(atPath: loginConfig) }
            step = .failed(Self.failure(from: model.viewErrors))
            registration = nil
            return
        }
        registration = nil
        if plan == .fresh {
            let tunnelWasUp = viewModel.vpnDisplayState != .disconnected
            do {
                try JetBoxIdentity.install(staging: loginConfig, into: activeConfig)
            } catch {
                AppLogger.shared.log("JetBox: не удалось поставить новый конфиг: \(error.localizedDescription)")
                step = .failed(.tunnelFailed)
                return
            }
            // Работающий туннель держит прежнюю личность в памяти — его нужно
            // перезапустить, иначе «подключено» покажет старое подключение.
            await stopTunnel(viewModel: viewModel)
            if Task.isCancelled {
                // Обрыв (чужая или битая ссылка, «Отмена») до фиксации замены:
                // прежний конфиг на место, туннель — как был до сценария.
                JetBoxIdentity.rollback(into: activeConfig)
                if tunnelWasUp { viewModel.connect() }
                AppLogger.shared.log("JetBox: замена прервана, прежнее подключение восстановлено")
                return
            }
        }
        // Фиксация замены: дальше обрыв только прекращает ожидание туннеля.
        JetBoxStore.remember(payload)
        if plan == .fresh { JetBoxIdentity.discardBackup(for: activeConfig) }
        AppLogger.shared.log("JetBox: устройство зарегистрировано на объекте (\(clock.lap()) мс)")

        // 3. Туннель.
        step = .connecting(payload)
        viewModel.connect()

        guard await waitForTunnel(viewModel: viewModel) else {
            if Task.isCancelled { return }
            AppLogger.shared.log("JetBox: туннель не поднялся за \(clock.lap()) мс")
            step = .failed(.tunnelFailed)
            return
        }
        AppLogger.shared.log("JetBox: туннель поднят (\(clock.lap()) мс)")

        // 4. Выход в интернет.
        // `x=0` (облако): выход по умолчанию не включаем, клиент включит сам.
        // «Только дом»: выход не включаем вовсе (JetBoxEdition).
        let exitOutcome: ExitOutcome
        if JetBoxEdition.appliesExit(payload: payload, homeOnly: JetBoxEdition.homeOnly) {
            step = .selectingExit(payload)
            exitOutcome = await resolveExitNode(payload: payload, viewModel: viewModel)
        } else {
            exitOutcome = .none
        }
        AppLogger.shared.log("JetBox: выход определён (\(clock.lap()) мс), всего \(clock.total()) мс")
        switch exitOutcome {
        case .selected(let name):
            JetBoxStore.rememberExitNode(name)
            step = .protected(exitNode: name)
            JetBoxNotifications.requestIfNeeded()
        case .ambiguous(let options):
            step = Self.stepForAmbiguousExit(payload: payload, options: options, style: JetBoxStyle.current,
                                             homeOnly: JetBoxEdition.homeOnly)
            if case .protected = step {
                AppLogger.shared.log("JetBox: выбор выхода не показываем (стиль «простое» или «только дом»), как «Пока не выбирать»")
                JetBoxNotifications.requestIfNeeded()
            }
        case .none:
            step = .protected(exitNode: nil)
            JetBoxNotifications.requestIfNeeded()
        }
    }

    /// Останавливает туннель и ждёт, пока расширение доложит `.disconnected`.
    /// Если включено «Подключать автоматически», система может поднять туннель
    /// сама — это не страшно: новый конфиг к этому моменту уже на месте.
    /// Ждёт и при обрыве сценария: откату нужен остановленный туннель, иначе
    /// прежний конфиг не перечитается. Поэтому пауза не через Task.sleep — та
    /// в отменённой задаче возвращается сразу.
    private func stopTunnel(viewModel: ViewModel) async {
        guard viewModel.vpnDisplayState != .disconnected else { return }
        viewModel.performClose()
        let deadline = Date().addingTimeInterval(stopTimeout)
        while Date() < deadline {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done.resume() }
            }
            if viewModel.vpnDisplayState == .disconnected { return }
        }
        AppLogger.shared.log("JetBox: туннель не остановился за \(Int(stopTimeout)) с, подключаемся заново")
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

    /// Выход из ссылки не определился сам. «Техно» спрашивает человека;
    /// «простое» выбора выхода не показывает нигде (замечание Алексея
    /// 21.11.2026) — ведёт себя как «Пока не выбирать». Сменить выход можно
    /// только в «техно».
    nonisolated static func stepForAmbiguousExit(payload: JetBoxLinkPayload, options: [String], style: JetBoxStyle,
                                                 homeOnly: Bool = false) -> Step {
        if homeOnly { return .protected(exitNode: nil) }
        switch style {
        case .simple: return .protected(exitNode: nil)
        case .techno: return .chooseExit(payload, options: options)
        }
    }

    private enum ExitOutcome {
        case selected(String)
        case ambiguous([String])
        case none
    }

    /// Выбор выхода в интернет. Ядро NetBird само включает выход, у которого
    /// на сервере `skipAutoApply=false` (routemanager/manager.go,
    /// pickPreferredExitNode); при `skipAutoApply=true` выход только разрешён,
    /// и выбирает его клиент — здесь. Имя маршрута приходит в ссылке (`e=`);
    /// если его нет или он не нашёлся — работает фолбэк. В «только дом» сюда
    /// не заходим, а выход снимают JetBoxHomeOnlyGuard и сетевое расширение.
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
        case .idle, .signingIn, .protected, .failed:
            return nil
        }
    }

    /// Состояния, из которых повторный приход той же ссылки должен начать
    /// сценарий заново, а не быть проигнорированным.
    private var isRestartable: Bool {
        switch step {
        case .ready, .confirmSwitch, .failed, .idle, .protected: return true
        case .signingIn, .registering, .connecting, .selectingExit, .chooseExit: return false
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

#if DEBUG
extension JetBoxOnboarding {
    /// Только для съёмки в симуляторе: экран по ссылке на нужном шаге без сети.
    /// `-JetBoxFlowDemo ready|switch|working|exits|protected|failed`.
    func showDemoIfRequested() {
        guard let raw = UserDefaults.standard.string(forKey: "JetBoxFlowDemo") else { return }
        let payload = JetBoxLinkPayload(setupKey: "3f6c2a9e-0d41-4c7b-9a55-8e21b07c4d19",
                                        managementURL: "https://netbird.jet-net.net",
                                        exitNodeName: "home-ivanov",
                                        boxName: "Lakeview Home")
        switch raw {
        case "ready": step = .ready(payload)
        case "switch": step = .confirmSwitch(payload, current: "Country House")
        case "working": step = .connecting(payload)
        // Через то же правило, что и настоящий сценарий: в «только дом» и в
        // «простом» выбора нет — покажется «подключено».
        case "exits": step = Self.stepForAmbiguousExit(payload: payload,
                                                      options: ["Lakeview Home", "Country House", "Downtown Office"],
                                                      style: JetBoxStyle.current, homeOnly: JetBoxEdition.homeOnly)
        case "protected": step = .protected(exitNode: "Lakeview Home")
        case "failed": step = .failed(.offline)
        case "signing": step = .signingIn
        case "expired": step = .failed(.loginExpired)
        default: break
        }
    }
}
#endif

#endif

/// Время этапов подключения — для журнала: клиент жалуется «подключается
/// минуту», а по журналу видно, какой этап её съел.
private struct StageClock {
    private let start = Date()
    private var last = Date()

    mutating func lap() -> Int {
        let now = Date()
        defer { last = now }
        return Int(now.timeIntervalSince(last) * 1000)
    }

    func total() -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}
