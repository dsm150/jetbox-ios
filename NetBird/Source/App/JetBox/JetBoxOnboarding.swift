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
    /// JetBox safety (сборка США): ссылка без верной подписи.
    case notFromJetBox
    case offline
    case managementUnreachable(String?)
    case keyRejected(String?)
    case tunnelFailed
    /// Ссылка входа из письма просрочена или уже использована (410).
    case loginExpired
    /// У JetBox клиента уже предельное число устройств (409 device_limit).
    case deviceLimit
    /// У аккаунта нет живого JetBox (409 not_available при входе по почте, 1.0 (33)).
    case notAvailable
    /// Кабинет ограничил частоту подтверждений (429).
    case loginRateLimited
    case other(String)

    var title: String {
        switch self {
        case .brokenLink: return JBText.errBrokenTitle
        case .foreignServer: return JBText.errForeignTitle
        case .notFromJetBox: return JBText.errUnsignedTitle
        case .offline: return JBText.errOfflineTitle
        case .managementUnreachable: return JBText.errUnreachableTitle
        case .keyRejected: return JBText.errKeyTitle
        case .tunnelFailed: return JBText.errTunnelTitle
        case .loginExpired: return JBText.errLoginExpiredTitle
        case .deviceLimit: return JBText.errDeviceLimitTitle
        case .notAvailable: return JBText.errUnreachableTitle
        case .loginRateLimited: return JBText.errLoginRateTitle
        case .other: return JBText.errGenericTitle
        }
    }

    var message: String {
        switch self {
        case .brokenLink: return JBText.errBrokenBody
        case .foreignServer: return JBText.errForeignBody
        case .notFromJetBox: return JBText.errUnsignedBody
        case .offline: return JBText.errOfflineBody
        case .managementUnreachable: return JBText.errUnreachableBody
        case .keyRejected: return JBText.errKeyBody
        case .tunnelFailed: return JBText.errTunnelBody
        case .loginExpired: return JBText.errLoginExpiredBody
        case .deviceLimit: return JBText.errDeviceLimitBody
        case .notAvailable: return JBText.loginNotAvailable
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
        case .brokenLink, .foreignServer, .notFromJetBox, .offline, .tunnelFailed,
             .loginExpired, .deviceLimit, .notAvailable, .loginRateLimited: return nil
        }
    }

    /// Ссылку входа повторять бесполезно — нужна новая: вместо «Повторить»
    /// кнопка ведёт на экран email.
    var asksForNewLoginLink: Bool { self == .loginExpired }

    /// Повтор имеет смысл не всегда: испорченную ссылку повторять нечем.
    var isRetryable: Bool {
        switch self {
        case .brokenLink, .foreignServer, .notFromJetBox, .loginExpired, .deviceLimit: return false
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
        /// Ссылка разобрана. Русская сборка ждёт нажатия единственной кнопки;
        /// сборка США подключается сама, как только есть ViewModel.
        case ready(JetBoxLinkPayload)
        /// Ссылка ведёт на другую коробку — спрашиваем подтверждение (только
        /// русская сборка: в США замена идёт без вопроса).
        case confirmSwitch(JetBoxLinkPayload, current: String)
        /// Регистрируем устройство по setup key.
        case registering(JetBoxLinkPayload)
        /// Поднимаем туннель.
        case connecting(JetBoxLinkPayload)
        /// Туннель есть, ищем и включаем выход в интернет.
        case selectingExit(JetBoxLinkPayload)
        /// Выход не определился сам — просим выбрать.
        case chooseExit(JetBoxLinkPayload, options: [String])
        /// Сборка США (1.0 (32)): объяснение перед системным запросом iOS
        /// «Add VPN Configurations» — когда профиля JetBox на iPhone ещё нет.
        case explainVPN
        /// Готово. Экран «You are protected» — только русская сборка: в США
        /// сценарий сразу возвращает на главный экран.
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

    /// Сборка США (решение Алексея 23.11.2026, сборка 26): подписанная ссылка
    /// подключает сразу — без экрана подтверждения, без вопроса о замене и без
    /// экрана «готово». Ход подключения показывает главный экран
    /// («Connecting…» → «Protected»), экран сценария — только отказы.
    /// Русская сборка — как раньше, с кнопкой. В тестах подменяется.
    var autoConnects: Bool = JetBoxOnboarding.editionAutoConnects

    nonisolated static var editionAutoConnects: Bool {
        #if JETBOX_US
        return true
        #else
        return false
        #endif
    }

    /// ViewModel приложения: без неё сценарий не запустить. Ссылка может
    /// прийти раньше (холодный старт) — тогда сценарий ждёт в `.ready`.
    private weak var viewModel: ViewModel?

    /// Ссылка на ту же коробку (США): включить туннель, если он выключен.
    /// true — включали. В тестах подменяется.
    lazy var resumeTunnel: () -> Bool = { [weak self] in
        guard let viewModel = self?.viewModel, viewModel.vpnDisplayState == .disconnected else { return false }
        viewModel.connect()
        return true
    }

    // MARK: Объяснение перед запросом VPN (1.0 (32))

    /// Показывать ли экран перед системным запросом iOS. Сборка США.
    var explainsVPN: Bool = JetBoxOnboarding.editionAutoConnects
    /// Есть ли на iPhone VPN-профиль JetBox. В тестах подменяется.
    lazy var vpnProfileExists: () async -> Bool = { [weak self] in
        guard let adapter = self?.viewModel?.networkExtensionAdapter else { return true }
        return await adapter.hasOurProfile()
    }
    private var vpnExplainWaiter: CheckedContinuation<Bool, Never>?
    private var stepBeforeVPNExplain: Step = .idle

    /// Перед первым `connect()`: профиля нет — экран-объяснение и ждём
    /// «Continue». false — экран закрыли или сценарий отменён.
    func explainVPNIfNeeded() async -> Bool {
        guard explainsVPN, !(await vpnProfileExists()) else { return true }
        cancelVPNExplain()
        stepBeforeVPNExplain = step
        step = .explainVPN
        AppLogger.shared.log("JetBox: no VPN profile yet — explaining before the iOS prompt")
        let go = await withCheckedContinuation { (waiter: CheckedContinuation<Bool, Never>) in
            vpnExplainWaiter = waiter
        }
        if step == .explainVPN { step = stepBeforeVPNExplain }
        return go
    }

    /// Кнопка «Continue» на экране-объяснении.
    func continueAfterVPNExplain() {
        let waiter = vpnExplainWaiter
        vpnExplainWaiter = nil
        waiter?.resume(returning: true)
    }

    private func cancelVPNExplain() {
        let waiter = vpnExplainWaiter
        vpnExplainWaiter = nil
        waiter?.resume(returning: false)
    }

    /// Подключение с главного экрана или из виджета: в сборке США — через
    /// объяснение, если профиля ещё нет.
    func connectTunnel(viewModel: ViewModel) {
        Task { @MainActor in
            if await explainVPNIfNeeded() { viewModel.connect() }
        }
    }

    func attach(_ viewModel: ViewModel) {
        self.viewModel = viewModel
        if autoConnects, case .ready(let payload) = step, flowTask == nil {
            start(payload: payload, viewModel: viewModel)
        }
    }

    /// Экран сценария поверх главного. В сборке США — только вход по ссылке
    /// из письма, отказы и (теоретически) выбор выхода.
    var isPresenting: Bool {
        guard autoConnects else { return step != .idle }
        switch step {
        case .signingIn, .failed, .chooseExit, .explainVPN: return true
        case .idle, .ready, .confirmSwitch, .registering, .connecting, .selectingExit, .protected: return false
        }
    }

    /// Сборка США: идёт подключение по ссылке без экрана сценария —
    /// главный экран показывает «Connecting…».
    var isConnectingInBackground: Bool { autoConnects && activePayload != nil && !isPresenting }

    /// Коробка, к которой идёт подключение, — для главного экрана, пока
    /// запись ещё не сохранена (первый вход) или сохранена прежняя (замена).
    var connectingBox: JetBoxBox? {
        guard isConnectingInBackground, let payload = activePayload else { return nil }
        return JetBoxStore.box(for: payload)
    }

    /// Наша ссылка, пришедшая до согласия «какие данные собираем» (сборка США):
    /// ждёт, пока человек не примет экран согласия, и только потом идёт в сеть.
    private var pendingURL: URL?
    private var pendingTrusted = false
    /// Нужен ли экран согласия; в тестах подменяется.
    var needsDataConsent: () -> Bool = { JetBoxDataConsent.needsConsent() }

    /// Согласие принято — ссылку, отложенную до него, отрабатываем сейчас.
    func resumeAfterDataConsent() {
        guard let url = pendingURL else { return }
        pendingURL = nil
        handle(url, trusted: pendingTrusted)
    }

    // MARK: Вход по ссылке

    /// Точка входа из `onOpenURL` / `onContinueUserActivity`.
    /// Возвращает true, если ссылка наша и обработана.
    /// `trusted` — ссылка из ответа verify встроенного API (вход по email):
    /// пришла по TLS, подпись JetBox safety для неё не требуется.
    @discardableResult
    func handle(_ url: URL, trusted: Bool = false) -> Bool {
        let rules: JetBoxLinkRules = trusted ? .current.trustingSource : .current
        if needsDataConsent() {
            let ours = JetBoxLoginLink.parse(url) != .notOurs || JetBoxLink.parse(url, rules: rules) != .notOurs
            if ours {
                AppLogger.shared.log("JetBox: link held until data consent is accepted")
                pendingURL = url
                pendingTrusted = trusted
            }
            return ours
        }
        switch JetBoxLoginLink.parse(url) {
        case .token(let token):
            if step == .signingIn, token == lastLoginToken { return true }
            AppLogger.shared.log("JetBox: email login link accepted")
            JetBoxStore.skipUpstreamOnboarding()
            startLogin(token: token)
            return true
        case .broken:
            AppLogger.shared.log("JetBox: email login link without a valid token, not going online")
            flowTask?.cancel()
            lastLoginToken = nil
            step = .failed(.brokenLink)
            return true
        case .notOurs:
            break
        }

        switch JetBoxLink.parse(url, rules: rules) {
        case .notOurs:
            return false

        case .unsigned:
            // JetBox safety: подписи нет или она не наша — ни вопроса, ни
            // регистрации, текущее подключение не трогаем.
            AppLogger.shared.log("JetBox: link signature missing or invalid, not going online")
            flowTask?.cancel()
            step = .failed(.notFromJetBox)
            return true

        case .broken:
            AppLogger.shared.log("JetBox: link fails format check, not going online")
            flowTask?.cancel()
            step = .failed(.brokenLink)
            return true

        case .foreignServer:
            // Чужой сервер: ни вопроса, ни регистрации, текущее подключение не трогаем.
            AppLogger.shared.log("JetBox: server address in link is outside the allowed domain, not going online")
            flowTask?.cancel()
            step = .failed(.foreignServer)
            return true

        case .payload(let payload):
            // Повторное открытие той же ссылки посреди работы сценария не
            // должно откатывать его в начало.
            if let active = activePayload, active == payload, !isRestartable {
                return true
            }
            AppLogger.shared.log("JetBox: link accepted, box \(payload.displayName), key \(payload.maskedKey)")
            JetBoxStore.skipUpstreamOnboarding()
            flowTask?.cancel()
            lastPayload = payload

            if let box = JetBoxStore.currentBox, !box.isSameConnection(as: payload) {
                if autoConnects {
                    // США: замена без вопроса, как раньше после «Switch».
                    AppLogger.shared.log("JetBox: link leads to another box, replacing without a question")
                    begin(payload)
                } else {
                    step = .confirmSwitch(payload, current: box.displayName)
                }
            } else {
                // Тот же JetBox, а имени в записи не было — запоминаем сразу,
                // даже если клиент нажмёт «Отмена».
                if let named = JetBoxStore.currentBox?.named(by: payload) {
                    JetBoxStore.currentBox = named
                }
                if autoConnects, JetBoxStore.currentBox != nil {
                    // США: ссылка на ту же коробку — без повторной регистрации.
                    // Туннель выключен — включаем (клик по ссылке = подключение,
                    // Алексей 23.11.2026), включён — просто главный экран.
                    let resumed = resumeTunnel()
                    AppLogger.shared.log(resumed
                        ? "JetBox: link leads to the current box, tunnel was off — connecting"
                        : "JetBox: link leads to the current box, showing the home screen")
                    lastPayload = nil
                    step = .idle
                } else if autoConnects {
                    begin(payload)
                } else {
                    step = .ready(payload)
                }
            }
            return true
        }
    }

    /// США: сразу в сценарий. Без ViewModel (холодный старт, тесты) шаг
    /// остаётся `.ready` до `attach`.
    private func begin(_ payload: JetBoxLinkPayload) {
        step = .ready(payload)
        if let viewModel { start(payload: payload, viewModel: viewModel) }
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
                finish(exitNode: name)
            } else {
                finish(exitNode: nil)
            }
        }
    }

    func dismiss() {
        cancelVPNExplain()
        flowTask?.cancel()
        flowTask = nil
        registration = nil
        lastPayload = nil
        lastLoginToken = nil
        step = .idle
    }

    // MARK: - Выход

    /// Меняется при каждом выходе: главный экран по нему сбрасывает форму входа
    /// и перерисовывается (запись JetBox живёт в UserDefaults, SwiftUI её не видит).
    @Published private(set) var signOutCount = 0

    /// «Sign out»: туннель выключен, профиль NetBird на телефоне стёрт, записи
    /// JetBox нет — дальше как после свежей установки. Устройство на сервере
    /// остаётся (API для этого нет).
    func signOut(stopTunnel: @MainActor () async -> Void,
                 files: JetBoxSignOut.Files? = JetBoxSignOut.Files.active()) async {
        dismiss()
        await stopTunnel()
        let removed = files.map { JetBoxSignOut.wipe($0) } ?? 0
        JetBoxStore.currentBox = nil
        deleteAppToken()
        JetBoxAdvancedAccess.defaults.removeObject(forKey: JetBoxDiagnostics.maskedEmailKey)
        signOutCount += 1
        AppLogger.shared.log("JetBox: sign out — tunnel stopped, profile files removed: \(removed)")
    }

    func signOut(viewModel: ViewModel) async {
        await signOut(stopTunnel: { await JetBoxSignOut.stopTunnel(viewModel) })
    }

    // MARK: - Выход с освобождением места (1.0 (33), паритет с Android)

    enum SignOutResult: Equatable {
        /// Место освобождено (или токена нет — выход только на телефоне); вышли.
        case signedOut
        /// Кабинет не ответил или отказал: устройство занимает место. Решает
        /// человек — «Try again» / «Sign out on this iPhone only» / «Cancel».
        case serverDidNotAnswer
    }

    /// Пауза перед повтором revoke после обрыва. В тестах — 0.
    var revokeRetryDelay: UInt64 = 1_500_000_000

    /// «Sign out»: сначала `device/revoke` к Кабинету — при живом туннеле, как
    /// Android, — потом локальный выход. Отозванное устройство теряет пир, туннель
    /// (и ответ, если запрос шёл через дом) рвётся, поэтому при обрыве туннель
    /// выключается и запрос повторяется напрямую: повтор погашенным токеном
    /// Кабинет отвечает 200. Без токена (вход по ссылке) — только на телефоне.
    func signOutReleasingPlace(stopTunnel: @MainActor () async -> Void,
                               files: JetBoxSignOut.Files? = JetBoxSignOut.Files.active()) async -> SignOutResult {
        guard let token = loadAppToken() else {
            AppLogger.shared.log("JetBox: sign out — no app token, this iPhone only")
            await signOut(stopTunnel: stopTunnel, files: files)
            return .signedOut
        }
        var outcome = await loginAPI.revokeDevice(token: token)
        if outcome == .unreachable {
            await stopTunnel()
            try? await Task.sleep(nanoseconds: revokeRetryDelay)
            outcome = await loginAPI.revokeDevice(token: token)
        }
        switch outcome {
        case .revoked, .unauthorized:
            await signOut(stopTunnel: stopTunnel, files: files)
            return .signedOut
        case .unreachable, .failed:
            AppLogger.shared.log("JetBox: sign out — place not released, asking")
            return .serverDidNotAnswer
        }
    }

    func signOutReleasingPlace(viewModel: ViewModel) async -> SignOutResult {
        await signOutReleasingPlace(stopTunnel: { await JetBoxSignOut.stopTunnel(viewModel) })
    }

    // MARK: - Удаление аккаунта (Apple 5.1.1(v), 1.0 (14))

    enum AccountDeletion: Equatable {
        /// Кабинет снял доступ (200) или токен уже погашен (401) — вышли локально.
        case deleted
        /// Токена нет (профиль до 1.0 (14)) — вышли локально, просим войти заново.
        case signInAgain
        /// 409 last_owner: удалить может только поддержка (1.0 (32)).
        case lastOwner(support: String)
        /// 5xx, лимит, нет сети — ничего не стёрто.
        case failed
    }

    /// Адрес поддержки США, если Кабинет не прислал свой (политика, раздел контактов).
    nonisolated static let defaultSupportEmail = "dev@ai-boss.us"

    /// Когда отправлено удаление (1.0 (32)). Кабинет снимает доступ сразу, туннель
    /// рвётся, ответ теряется; повтор приходит уже с 401 — это и есть успех.
    static let deleteSentKey = "jetbox.accountDeleteSentAt"
    var deleteDefaults: UserDefaults = JetBoxAdvancedAccess.defaults
    /// Пауза перед автоматическим повтором после обрыва. В тестах — 0.
    var deleteRetryDelay: UInt64 = 1_500_000_000

    private var deleteWasSent: Bool {
        guard let sent = deleteDefaults.object(forKey: Self.deleteSentKey) as? Date else { return false }
        return Date().timeIntervalSince(sent) < 24 * 3600
    }

    var loadAppToken: () -> String? = { JetBoxAppToken.load() }
    var deleteAppToken: () -> Void = { JetBoxAppToken.delete() }

    /// Текст для чистого экрана входа после выхода; забирает главный экран.
    private(set) var loginNotice: String?

    func takeLoginNotice() -> String? {
        defer { loginNotice = nil }
        return loginNotice
    }

    func deleteAccount(stopTunnel: @MainActor () async -> Void,
                       files: JetBoxSignOut.Files? = JetBoxSignOut.Files.active()) async -> AccountDeletion {
        guard let token = loadAppToken() else {
            AppLogger.shared.log("JetBox: account deletion — no app token, signing out locally")
            loginNotice = JBText.deleteSignInAgain
            await signOut(stopTunnel: stopTunnel, files: files)
            return .signInAgain
        }
        let alreadySent = deleteWasSent
        if !alreadySent { deleteDefaults.set(Date(), forKey: Self.deleteSentKey) }
        var outcome = await loginAPI.deleteAccount(token: token)
        var retried = false
        if outcome == .unreachable {
            retried = true
            // Удаление могло уже пройти: Кабинет отключил устройство, пир пропал,
            // ответ через дом не дошёл. Туннель выключаем, чтобы повтор пошёл
            // напрямую, а не в мёртвый туннель (1.0 (34), как revoke в 33).
            await stopTunnel()
            try? await Task.sleep(nanoseconds: deleteRetryDelay)
            outcome = await loginAPI.deleteAccount(token: token)
        }
        switch outcome {
        case .deleted:
            return await finishDeletion(stopTunnel: stopTunnel, files: files, notice: JBText.deleteDone)
        case .unauthorized:
            // 401 сразу после отправленного удаления — успех, а не «токен погашен».
            let sent = alreadySent || retried
            return await finishDeletion(stopTunnel: stopTunnel, files: files,
                                        notice: sent ? JBText.deleteDone : JBText.deleteSignInAgain)
        case .lastOwner(let support):
            deleteDefaults.removeObject(forKey: Self.deleteSentKey)
            JetBoxSupportContact.remember(support)
            return .lastOwner(support: support.isEmpty ? Self.defaultSupportEmail : support)
        case .unreachable, .failed:
            return .failed
        }
    }

    private func finishDeletion(stopTunnel: @MainActor () async -> Void,
                                files: JetBoxSignOut.Files?, notice: String) async -> AccountDeletion {
        deleteDefaults.removeObject(forKey: Self.deleteSentKey)
        loginNotice = notice
        await signOut(stopTunnel: stopTunnel, files: files)
        return .deleted
    }

    func deleteAccount(viewModel: ViewModel) async -> AccountDeletion {
        await deleteAccount(stopTunnel: { await JetBoxSignOut.stopTunnel(viewModel) })
    }

    // MARK: - Вход по ссылке из письма

    private func startLogin(token: String) {
        flowTask?.cancel()
        lastPayload = nil
        lastLoginToken = token
        step = .signingIn
        let api = loginAPI
        flowTask = Task { @MainActor in
            #if DEBUG
            // Съёмка в симуляторе: сеть в нём не выключить. `-JetBoxVerifyDemoFail offline` —
            // первая проверка ссылки падает как «без сети», следующие идут на сервер.
            if UserDefaults.standard.string(forKey: "JetBoxVerifyDemoFail") == "offline", !Self.verifyDemoFailUsed {
                Self.verifyDemoFailUsed = true
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if Task.isCancelled { return }
                finishLogin(.offline)
                return
            }
            #endif
            let outcome = await api.verify(token: token, deviceName: Device.getName())
            if Task.isCancelled { return }
            finishLogin(outcome)
        }
    }

    #if DEBUG
    private static var verifyDemoFailUsed = false
    #endif

    private func finishLogin(_ outcome: JetBoxLoginAPI.VerifyOutcome) {
        switch outcome {
        case .connect(let url):
            // Токен израсходован: дальше обычный путь ссылки /connect —
            // маска сервера, проверка ключа; в США — сразу подключение,
            // в русской — «переключить?» и одна кнопка.
            lastLoginToken = nil
            flowTask = nil
            if !handle(url, trusted: true) { step = .failed(.brokenLink) }
        case .expired, .badCode:
            lastLoginToken = nil
            step = .failed(.loginExpired)
        case .deviceLimit:
            lastLoginToken = nil
            step = .failed(.deviceLimit)
        case .notAvailable:
            // Ссылка не израсходована (Кабинет её не гасит): «Try again» повторит.
            step = .failed(.notAvailable)
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
        cancelVPNExplain()
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
            AppLogger.shared.log("JetBox: replacing connection — registering a new device identity")
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
                AppLogger.shared.log("JetBox: could not install the new config: \(error.localizedDescription)")
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
                AppLogger.shared.log("JetBox: replacement aborted, previous connection restored")
                return
            }
        }
        // Фиксация замены: дальше обрыв только прекращает ожидание туннеля.
        JetBoxStore.remember(payload)
        if plan == .fresh { JetBoxIdentity.discardBackup(for: activeConfig) }
        JetBoxBackup.excludeProfileFiles()
        AppLogger.shared.log("JetBox: device registered (\(clock.lap()) ms)")

        // 3. Туннель. Профиля VPN ещё нет — сначала объяснение (сборка США, 1.0 (32)).
        step = .connecting(payload)
        guard await explainVPNIfNeeded(), !Task.isCancelled else { return }
        step = .connecting(payload)
        viewModel.connect()

        guard await waitForTunnel(viewModel: viewModel) else {
            if Task.isCancelled { return }
            AppLogger.shared.log("JetBox: tunnel did not come up in \(clock.lap()) ms")
            step = .failed(.tunnelFailed)
            return
        }
        AppLogger.shared.log("JetBox: tunnel up (\(clock.lap()) ms)")

        // 3а. Дом. «Готово» — только когда отвечает коробка, до 90 с (JetBoxHomeReadiness).
        await JetBoxHomeReadiness.shared.waitUntilReady(viewModel: viewModel)
        if Task.isCancelled { return }
        AppLogger.shared.log("JetBox: waited for home (\(clock.lap()) ms)")

        // 4. Выход в интернет.
        // `x=0` (облако): выход по умолчанию не включаем, клиент включит сам.
        // «Только дом»: только выход своей коробки, по имени из `e` (JetBoxEdition).
        let exitOutcome: ExitOutcome
        if JetBoxEdition.appliesExit(payload: payload, homeOnly: JetBoxEdition.homeOnly) {
            step = .selectingExit(payload)
            exitOutcome = await resolveExitNode(payload: payload, viewModel: viewModel)
        } else {
            exitOutcome = .none
        }
        AppLogger.shared.log("JetBox: exit resolved (\(clock.lap()) ms), total \(clock.total()) ms")
        switch exitOutcome {
        case .selected(let name):
            JetBoxStore.rememberExitNode(name)
            finish(exitNode: name)
        case .ambiguous(let options):
            let next = Self.stepForAmbiguousExit(payload: payload, options: options, style: JetBoxStyle.current,
                                                 homeOnly: JetBoxEdition.homeOnly)
            if case .protected(let exitNode) = next {
                AppLogger.shared.log("JetBox: exit picker not shown (simple style or home only), same as Not now")
                finish(exitNode: exitNode)
            } else {
                step = next
            }
        case .none:
            finish(exitNode: nil)
        }
    }

    /// Сценарий дошёл до конца. Русская сборка показывает «готово»; сборка
    /// США сразу отдаёт главный экран — там уже «Protected».
    private func finish(exitNode: String?) {
        if autoConnects {
            AppLogger.shared.log("JetBox: connected by link, back to the home screen")
            flowTask = nil
            lastPayload = nil
            step = .idle
        } else {
            step = .protected(exitNode: exitNode)
        }
        JetBoxNotifications.requestIfNeeded()
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
        AppLogger.shared.log("JetBox: tunnel did not stop in \(Int(stopTimeout)) s, reconnecting")
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
        #if JETBOX_US
        return .protected(exitNode: nil)
        #else
        if homeOnly { return .protected(exitNode: nil) }
        switch style {
        case .simple: return .protected(exitNode: nil)
        case .techno: return .chooseExit(payload, options: options)
        }
        #endif
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
    /// если его нет или он не нашёлся — работает фолбэк. В «только дом» —
    /// только имя из ссылки: чужой выход снимут JetBoxHomeOnlyGuard и расширение.
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

        // «Только дом»: никаких догадок — своего выхода нет в маршрутах, значит без выхода.
        #if JETBOX_US
        AppLogger.shared.log("JetBox: home only — own box exit not in routes (\(nodes.count) others)")
        return .none
        #else
        if JetBoxEdition.homeOnly {
            AppLogger.shared.log("JetBox: home only — own box exit not in routes (\(nodes.count) others)")
            return .none
        }

        // 2. Ровно один выход — выбираем его.
        if nodes.count == 1, let only = nodes.first {
            await select(only, in: routes)
            AppLogger.shared.log("JetBox: exit selected automatically — the only one available")
            return .selected(only.name)
        }

        // 3. Ноль или больше одного — спрашиваем человека.
        AppLogger.shared.log("JetBox: exit from link not found, showing picker (\(nodes.count) options)")
        return .ambiguous(nodes.map(\.name))
        #endif
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
        case .idle, .signingIn, .protected, .failed, .explainVPN:
            return nil
        }
    }

    /// Состояния, из которых повторный приход той же ссылки должен начать
    /// сценарий заново, а не быть проигнорированным.
    private var isRestartable: Bool {
        switch step {
        case .ready, .confirmSwitch, .failed, .idle, .protected: return true
        case .signingIn, .registering, .connecting, .selectingExit, .chooseExit, .explainVPN: return false
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
                                        managementURL: JetBoxConfig.defaultManagementURL,
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
        case "unsigned": step = .failed(.notFromJetBox)
        case "vpn": step = .explainVPN
        case "unreachable": step = .failed(.managementUnreachable(nil))
        case "tunnel": step = .failed(.tunnelFailed)
        case "devices": step = .failed(.deviceLimit)
        case "notavailable": step = .failed(.notAvailable)
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
