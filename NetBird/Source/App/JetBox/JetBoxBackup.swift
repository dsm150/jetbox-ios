//
//  JetBoxBackup.swift
//  JetBox
//
//  Ключ WireGuard — личность телефона в сети JetBox, он не должен уезжать
//  с бэкапом iCloud/iTunes на новый телефон (находка AppDev на Android,
//  22.11.2026). Апстрим исключает файлы профиля при запуске
//  (ProfileManager.excludeProfileStorageFromBackup), но ядро пишет конфиг
//  заменой файла — пометка слетает до следующего запуска. Поэтому:
//  исключаем весь контейнер App Group (пометка на папке покрывает всё
//  содержимое) и заново помечаем файлы после регистрации. Токен приложения —
//  в Keychain «только это устройство» (JetBoxAppToken).
//
//  Запись JetBox в UserDefaults приложения в бэкап попадает. Если она
//  вернулась на новый телефон без конфига — стираем её: человек входит по
//  email заново, а не смотрит на коробку, к которой не подключиться.
//

#if os(iOS)
import Foundation

enum JetBoxBackup {

    static func excludeProfileFiles() {
        var urls: [URL] = []
        if let root = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: GlobalConstants.userPreferencesSuiteName) {
            urls.append(root)
        }
        if let config = Preferences.configFile() {
            urls += [config, JetBoxIdentity.stagingPath(for: config), JetBoxIdentity.backupPath(for: config)]
                .map { URL(fileURLWithPath: $0) }
        }
        if let state = Preferences.stateFile() { urls.append(URL(fileURLWithPath: state)) }
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            exclude(url)
        }
    }

    /// Запись есть, а конфига нет — запись приехала из бэкапа на другой телефон.
    static func isOrphaned(box: JetBoxBox?, configPath: String?, fileExists: (String) -> Bool) -> Bool {
        guard box != nil, let configPath, !configPath.isEmpty else { return false }
        return !fileExists(configPath)
    }

    static func dropOrphanedBoxIfNeeded() {
        let box = JetBoxStore.currentBox
        guard box != nil else { return }
        guard isOrphaned(box: box, configPath: Preferences.configFile(),
                         fileExists: { FileManager.default.fileExists(atPath: $0) }) else { return }
        AppLogger.shared.log("JetBox: запись JetBox без конфига (восстановлена из бэкапа?) — нужен вход заново")
        JetBoxStore.currentBox = nil
        JetBoxAppToken.delete()
    }

    private static func exclude(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try url.setResourceValues(values)
        } catch {
            AppLogger.shared.log("JetBox: не удалось исключить из бэкапа \(url.lastPathComponent)")
        }
    }
}
#endif
