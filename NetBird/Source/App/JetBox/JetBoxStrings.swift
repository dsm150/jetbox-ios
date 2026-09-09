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
    static var readyHint: String { t("jetbox.ready.hint") }
    static var readyKeyLabel: String { t("jetbox.ready.key_label") }
    static var readyButton: String { t("jetbox.ready.button") }
    /// Объявление о собираемых данных под кнопкой подключения — требование
    /// App Review 5.4 («clear declaration … prior to any user action»).
    static var privacyNotice: String { t("jetbox.privacy.notice") }
    static var privacyMore: String { t("jetbox.privacy.more") }

    static var switchTitle: String { t("jetbox.switch.title") }
    static func switchMessage(_ from: String, _ to: String) -> String {
        String(format: String(localized: "jetbox.switch.message"), from, to)
    }
    static var switchConfirm: String { t("jetbox.switch.confirm") }

    static var registering: String { t("jetbox.progress.registering") }
    static var connecting: String { t("jetbox.progress.connecting") }
    static var selectingExit: String { t("jetbox.progress.selecting_exit") }

    static var protectedTitle: String { t("jetbox.protected.title") }
    static func protectedExit(_ name: String) -> String { t("jetbox.protected.exit", name) }
    static var protectedNoExit: String { t("jetbox.protected.no_exit") }

    // MARK: Выбор выхода

    static var exitPickerTitle: String { t("jetbox.exit.title") }
    static var exitPickerMessage: String { t("jetbox.exit.message") }
    static var exitPickerSkip: String { t("jetbox.exit.skip") }
    static var exitPickerEmpty: String { t("jetbox.exit.empty") }

    // MARK: Отказы

    static var errBrokenTitle: String { t("jetbox.error.broken.title") }
    static var errBrokenBody: String { t("jetbox.error.broken.body") }
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
    static var settingsServer: String { t("jetbox.settings.server") }
    static var settingsExit: String { t("jetbox.settings.exit") }
    static var settingsNoBox: String { t("jetbox.settings.no_box") }
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
}
