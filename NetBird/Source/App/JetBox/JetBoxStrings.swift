//
//  JetBoxStrings.swift
//  JetBox
//
//  Все тексты наших экранов — через каталог строк (Localizable.xcstrings).
//  Русский основной, английский вторым; язык берётся из настроек телефона.
//
//  Ключи собраны здесь, а не рассыпаны по вьюхам, чтобы:
//   1) переводчику была видна вся поверхность продукта одним списком;
//   2) опечатка в ключе ловилась компилятором, а не на экране клиента.
//

import Foundation

enum JBText {

    private static func t(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    private static func t(_ key: String.LocalizationValue, _ arg: String) -> String {
        String(format: String(localized: key), arg)
    }

    // MARK: Общее

    static var brand: String { "JetBox" }
    static var cancel: String { t("jetbox.common.cancel") }
    static var done: String { t("jetbox.common.done") }
    static var close: String { t("jetbox.common.close") }
    static var retry: String { t("jetbox.common.retry") }

    // MARK: Экран ссылки

    static var readyCaption: String { t("jetbox.ready.caption") }
    static var readyKeyLabel: String { t("jetbox.ready.key_label") }
    static var readyButton: String { t("jetbox.ready.button") }
    /// Объявление о собираемых данных под кнопкой подключения — требование
    /// App Review 5.4 («clear declaration … prior to any user action»).
    static var privacyNotice: String { t("jetbox.privacy.notice") }
    static var privacyMore: String { t("jetbox.privacy.more") }

    // MARK: Согласие «какие данные собираем» (сборка США, до входа)

    static var consentTitle: String { t("jetbox.consent.title") }
    static var consentIntro: String { t("jetbox.consent.intro") }
    static var consentEmailTitle: String { t("jetbox.consent.email.title") }
    static var consentEmailBody: String { t("jetbox.consent.email.body") }
    static var consentDeviceTitle: String { t("jetbox.consent.device.title") }
    static var consentDeviceBody: String { t("jetbox.consent.device.body") }
    static var consentNetworkTitle: String { t("jetbox.consent.network.title") }
    static var consentNetworkBody: String { t("jetbox.consent.network.body") }
    static var consentNever: String { t("jetbox.consent.never") }
    static var consentReadPolicy: String { t("jetbox.consent.read_policy") }
    static var consentAccept: String { t("jetbox.consent.accept") }

    static var switchTitle: String { t("jetbox.switch.title") }
    static func switchMessage(_ from: String, _ to: String) -> String {
        String(format: String(localized: "jetbox.switch.message"), from, to)
    }
    static var switchConfirm: String { t("jetbox.switch.confirm") }

    static var registering: String { t("jetbox.progress.registering") }
    static var connecting: String { t("jetbox.progress.connecting") }
    static var selectingExit: String { t("jetbox.progress.selecting_exit") }

    // MARK: Вход по email (сборка США)

    static var loginTitle: String { t("jetbox.login.title") }
    static var loginField: String { t("jetbox.login.field") }
    static var loginSend: String { t("jetbox.login.send") }
    static var loginSending: String { t("jetbox.login.sending") }
    static var loginInvalidEmail: String { t("jetbox.login.invalid_email") }
    static var loginSentTitle: String { t("jetbox.login.sent.title") }
    static func loginSentBody(_ email: String) -> String { t("jetbox.login.sent.body", email) }
    static var loginSentSpam: String { t("jetbox.login.sent.spam") }
    static var loginOpenMail: String { t("jetbox.login.open_mail") }
    static var loginResend: String { t("jetbox.login.resend") }
    static func loginResendWait(_ seconds: Int) -> String { t("jetbox.login.resend_wait", String(seconds)) }
    static var loginSentAgain: String { t("jetbox.login.sent_again") }
    static var loginAnother: String { t("jetbox.login.another") }
    static var loginRateLimited: String { t("jetbox.login.rate_limited") }
    static var loginOffline: String { t("jetbox.login.offline") }
    static var loginUnavailable: String { t("jetbox.login.unavailable") }
    static var loginSigningIn: String { t("jetbox.login.signing_in") }
    static var loginCodeLink: String { t("jetbox.login.code.link") }
    static var loginCodeTitle: String { t("jetbox.login.code.title") }
    static func loginCodeBody(_ email: String) -> String { t("jetbox.login.code.body", email) }
    static var loginCodeField: String { t("jetbox.login.code.field") }
    static var loginCodeSubmit: String { t("jetbox.login.code.submit") }
    static var loginCodeChecking: String { t("jetbox.login.code.checking") }
    static var loginCodeWrong: String { t("jetbox.login.code.wrong") }
    static func loginCodeWrongLeft(_ left: Int) -> String { t("jetbox.login.code.wrong_left", String(left)) }
    static var loginCodeExpired: String { t("jetbox.login.code.expired") }
    static var loginCodeResend: String { t("jetbox.login.code.resend") }
    static func loginCodeResendWait(_ seconds: Int) -> String { t("jetbox.login.code.resend_wait", String(seconds)) }
    static var loginCodeBack: String { t("jetbox.login.code.back") }
    static var errLoginExpiredTitle: String { t("jetbox.error.login_expired.title") }
    static var errLoginExpiredBody: String { t("jetbox.error.login_expired.body") }
    static var errLoginExpiredAction: String { t("jetbox.error.login_expired.action") }
    static var errDeviceLimitTitle: String { t("jetbox.error.device_limit.title") }
    static var errDeviceLimitBody: String { t("jetbox.error.device_limit.body") }
    static var errLoginRateTitle: String { t("jetbox.error.login_rate.title") }
    static var errLoginRateBody: String { t("jetbox.error.login_rate.body") }

    static var protectedTitle: String { t("jetbox.protected.title") }
    static func protectedExit(_ name: String) -> String { t("jetbox.protected.exit", name) }
    static var protectedNoExit: String { t("jetbox.protected.no_exit") }
    /// Экран «готово»: в сборке США с выходом своей коробки — «весь интернет через дом».
    static func protectedTitle(exitNode: String?) -> String {
        if JetBoxEdition.homeOnly { return allInternetHome ? t("jetbox.protected.title_all") : protectedTitle }
        return protectedTitle
    }
    static func protectedBody(exitNode: String?) -> String {
        if JetBoxEdition.homeOnly {
            if allInternetHome { return t("jetbox.protected.all") }
            return exitWarning ?? protectedNoExit
        }
        return exitNode.map(protectedExit) ?? protectedNoExit
    }

    // MARK: Выбор выхода

    static var exitPickerTitle: String { t("jetbox.exit.title") }
    static var exitPickerMessage: String { t("jetbox.exit.message") }
    static var exitPickerSkip: String { t("jetbox.exit.skip") }
    static var exitPickerEmpty: String { t("jetbox.exit.empty") }

    // MARK: Отказы

    static var errBrokenTitle: String { t("jetbox.error.broken.title") }
    static var errBrokenBody: String { t("jetbox.error.broken.body") }
    static var errForeignTitle: String { t("jetbox.error.foreign.title") }
    static var errForeignBody: String { t("jetbox.error.foreign.body") }
    static var errUnsignedTitle: String { t("jetbox.error.unsigned.title") }
    static var errUnsignedBody: String { t("jetbox.error.unsigned.body") }
    static var errOfflineTitle: String { t("jetbox.error.offline.title") }
    static var errOfflineBody: String { t("jetbox.error.offline.body") }
    static var errUnreachableTitle: String { t("jetbox.error.unreachable.title") }
    static var errUnreachableBody: String { t("jetbox.error.unreachable.body") }
    static var errKeyTitle: String { t("jetbox.error.key.title") }
    static var errKeyBody: String { t("jetbox.error.key.body") }
    static var errTunnelTitle: String { t("jetbox.error.tunnel.title") }
    static var errTunnelBody: String { t("jetbox.error.tunnel.body") }
    static var errGenericTitle: String { t("jetbox.error.generic.title") }
    static var errGenericBody: String { t("jetbox.error.generic.body") }
    static var errDetails: String { t("jetbox.error.details") }

    // MARK: Главный экран

    static var homeConnected: String { t("jetbox.home.connected") }
    /// Сборка США, тумблер «All internet through my JetBox» включён.
    /// «Protected by your JetBox» — только когда весь интернет правда идёт через
    /// дом: у записи есть выход своей коробки И маршрут по умолчанию стоит в
    /// применённых настройках туннеля (JetBoxTunnelState, пишет расширение).
    /// Одной записи или выбора в ядре мало — баг 1.0 (16).
    static var allInternetHome: Bool { allInternetHome(expected: JetBoxStore.allInternetHome) }
    static func allInternetHome(expected: Bool, inTunnel: Bool = JetBoxTunnelState.defaultRouteInTunnel()) -> Bool {
        expected && inTunnel
    }
    /// Выход своей коробки должен быть, а маршрута по умолчанию в туннеле нет.
    static var exitWarning: String? { exitWarning(expected: JetBoxStore.allInternetHome) }
    static func exitWarning(expected: Bool, inTunnel: Bool = JetBoxTunnelState.defaultRouteInTunnel()) -> String? {
        expected && !inTunnel ? t("jetbox.home.exit_missing") : nil
    }
    static var homeConnectedAll: String { t("jetbox.home.connected_all") }
    static var homeConnectedNow: String { allInternetHome ? homeConnectedAll : homeConnected }
    static var homeConnecting: String { t("jetbox.home.connecting") }
    static var homeDisconnecting: String { t("jetbox.home.disconnecting") }
    static var homeDisconnected: String { t("jetbox.home.disconnected") }
    static var homeOffline: String { t("jetbox.home.offline") }
    static var homeConnect: String { t("jetbox.home.connect") }
    static var homeDisconnect: String { t("jetbox.home.disconnect") }
    static var homeNoBoxTitle: String { t("jetbox.home.no_box.title") }
    static var homeNoBoxBody: String { t("jetbox.home.no_box.body") }
    static func homeExit(_ name: String) -> String { t("jetbox.home.exit", name) }
    static var homeExitNone: String { t("jetbox.home.exit_none") }
    static var homeChangeExit: String { t("jetbox.home.change_exit") }

    // MARK: Настройки

    static var settingsTitle: String { t("jetbox.settings.title") }
    static var settingsSectionBox: String { t("jetbox.settings.section.box") }
    static var settingsBoxName: String { t("jetbox.settings.name") }
    static var settingsExit: String { t("jetbox.settings.exit") }
    static var settingsNoBox: String { t("jetbox.settings.no_box") }
    static var settingsSignOut: String { t("jetbox.settings.sign_out") }
    static var settingsDeleteAccount: String { t("jetbox.settings.delete_account") }
    static var settingsDeleteTitle: String { t("jetbox.settings.delete_account.confirm_title") }
    static var settingsDeleteBody: String { t("jetbox.settings.delete_account.confirm_body") }
    static var settingsDeleteFailed: String { t("jetbox.settings.delete_account.failed") }
    static var deleteSignInAgain: String { t("jetbox.settings.delete_account.sign_in_again") }
    static var settingsSignOutTitle: String { t("jetbox.settings.sign_out.confirm_title") }
    static var settingsSectionApp: String { t("jetbox.settings.section.app") }
    static var settingsVersion: String { t("jetbox.settings.version") }
    static var settingsAdvanced: String { t("jetbox.settings.advanced") }
    static var settingsAdvancedFooter: String { t("jetbox.settings.advanced.footer") }
    static var settingsAdvancedUnlocked: String { t("jetbox.settings.advanced.unlocked") }
    static var settingsAdvancedAlready: String { t("jetbox.settings.advanced.already") }
    static var settingsAdvancedOff: String { t("jetbox.settings.advanced.off") }
    static var settingsAdvancedOffFooter: String { t("jetbox.settings.advanced.off_footer") }

    /// Обратный отсчёт «ещё N нажатий…». Единственная строка с формами
    /// множественного числа, поэтому идёт мимо `t(_:)`: выбрать форму по числу
    /// умеет только `localizedStringWithFormat` — `String(localized:)` формы
    /// не разрешает.
    static func settingsAdvancedHint(_ remaining: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("jetbox.settings.advanced.hint", comment: ""), remaining)
    }

    static var aboutTitle: String { t("jetbox.about.title") }
    static var aboutBody: String { t("jetbox.about.body") }
    static var aboutSite: String { t("jetbox.about.site") }
    static var aboutSource: String { t("jetbox.about.source") }
    /// Правообладатель зависит от редакции: см. `JetBoxEdition.aboutLegalKey`.
    static func aboutLegal(_ year: String) -> String {
        JetBoxEdition.homeOnly ? t("jetbox.about.legal.us", year) : t("jetbox.about.legal", year)
    }
    static var aboutLicense: String { t("jetbox.about.license") }

    // MARK: Нижняя панель и подробности подключения

    static var dockOn: String { t("jetbox.dock.on") }
    static var dockOnNow: String { allInternetHome ? t("jetbox.dock.on_all") : (exitWarning ?? dockOn) }
    static var dockConnecting: String { t("jetbox.dock.connecting") }
    static var dockOff: String { t("jetbox.dock.off") }
    static var dockOffline: String { t("jetbox.dock.offline") }
    static var dockUptime: String { t("jetbox.dock.uptime") }
    static var dockLatency: String { t("jetbox.dock.latency") }
    static var dockRoute: String { t("jetbox.dock.route") }
    static var dockDirect: String { t("jetbox.dock.direct") }
    static var dockRelayed: String { t("jetbox.dock.relayed") }
    static func milliseconds(_ value: Int) -> String { t("jetbox.dock.ms", String(value)) }
    static var detailsUptime: String { t("jetbox.details.uptime") }
    static var detailsLatency: String { t("jetbox.details.latency") }
    static var detailsRoute: String { t("jetbox.details.route") }
    static var detailsRelayed: String { t("jetbox.details.relayed") }
    static var detailsTraffic: String { t("jetbox.details.traffic") }
    static var routeNotDirect: String { t("jetbox.route.not_direct") }
    static var routeNotDirectShort: String { t("jetbox.route.not_direct_short") }

    /// Строка Connection. `compact` — плитка нижней панели (одна строка в
    /// треть ширины): там короткие «Relay» и «No direct link»; в строке экрана
    /// «простое» и в деталях — полные «Via relay» и «Can't reach your JetBox directly».
    static func route(_ route: JetBoxLiveStats.Route, compact: Bool = false) -> String {
        switch route {
        case .direct: return dockDirect
        case .relayed: return compact ? dockRelayed : detailsRelayed
        case .notDirect: return compact ? routeNotDirectShort : routeNotDirect
        }
    }

    // MARK: Стиль оформления и стиль «простое»

    static var styleTitle: String { t("jetbox.style.title") }
    static var styleSimple: String { t("jetbox.style.simple") }
    static var styleTechno: String { t("jetbox.style.techno") }
    static var simpleTapToConnect: String { t("jetbox.simple.tap_to_connect") }
    static var simpleWait: String { t("jetbox.simple.wait") }
    static var simpleOfflineHint: String { t("jetbox.simple.offline_hint") }
    static var simpleDetails: String { t("jetbox.simple.details") }
    static var simpleAboutTitle: String { t("jetbox.simple.about.title") }
    static var simpleAboutRouter: String { t("jetbox.simple.about.router") }
    static var simpleAboutGuard: String { t("jetbox.simple.about.guard") }
    static var simpleAboutApp: String { t("jetbox.simple.about.app") }
    static var simpleAboutPrivacy: String { t("jetbox.simple.about.privacy") }
    static var simpleAboutLinks: String { t("jetbox.simple.about.links") }
    static var simplePrivacyToggle: String { t("jetbox.simple.privacy_toggle") }

    // MARK: Соглашения

    static var legalSection: String { t("jetbox.legal.section") }
    static var legalPrivacy: String { t("jetbox.legal.privacy") }
    static var legalTerms: String { t("jetbox.legal.terms") }
    static var legalEULA: String { t("jetbox.legal.eula") }
    /// Сборка США (Алексей, 23.11.2026): в Legal — сайт, соглашение, политика.
    static var legalUSSite: String { t("jetbox.legal.us.site") }
    static var legalUSAgreement: String { t("jetbox.legal.us.agreement") }
    static var legalUSPrivacy: String { t("jetbox.legal.us.privacy") }
    /// Строка согласия с Markdown-ссылками на Terms и Privacy (App Review 5.1.1).
    static var legalConsent: String { t("jetbox.legal.consent") }
}
