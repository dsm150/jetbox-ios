//
//  JetBoxSignOut.swift
//  JetBox
//
//  «Sign out» в настройках (задача руководителя 22.11.2026, сборка 1.0 (13)).
//  Туннель выключается, профиль NetBird на телефоне стирается, запись JetBox
//  сбрасывается — приложение ведёт себя как свежая установка: в сборке США
//  снова экран входа по email. Устройство на сервере не трогаем (API нет).
//
//  Файлы профиля — те же, что стирает апстримовый «Remove Profile»
//  (profilemanager.ServiceManager.RemoveProfile + mobile.removeProfileEmail):
//  конфиг, state, prefs, account. Сам Remove здесь не годится: Go-менеджер
//  профилей не удаляет ни профиль по умолчанию, ни активный, а JetBox живёт
//  именно в активном.
//

import Foundation

#if os(iOS)

enum JetBoxSignOut {
    /// Файлы активного профиля, которые надо стереть при выходе.
    struct Files: Equatable {
        var configPath: String
        var statePath: String?
        var profileID: String

        /// Что стирает Remove Profile, плюс наши копии на время замены подключения.
        var paths: [String] {
            let config = URL(fileURLWithPath: configPath)
            let dir = config.deletingLastPathComponent()
            let stem = config.deletingPathExtension().lastPathComponent
            var list = [
                configPath,
                JetBoxIdentity.stagingPath(for: configPath),
                JetBoxIdentity.backupPath(for: configPath),
                dir.appendingPathComponent(stem + ".account.json").path,
                dir.appendingPathComponent(profileID + ".prefs.json").path,
            ]
            if let statePath { list.append(statePath) }
            return list
        }

        /// Пути активного профиля — у ядра, а не собранные руками.
        static func active() -> Files? {
            guard let config = Preferences.configFile(), !config.isEmpty else { return nil }
            let id = ProfileManager.shared.getActiveProfileID()
            return Files(configPath: config, statePath: Preferences.stateFile(), profileID: id)
        }
    }

    /// Стирает файлы профиля. Отсутствующие файлы — не ошибка.
    /// Возвращает, сколько файлов было и удалено.
    @discardableResult
    static func wipe(_ files: Files, fileManager: FileManager = .default) -> Int {
        var removed = 0
        for path in files.paths where fileManager.fileExists(atPath: path) {
            if (try? fileManager.removeItem(atPath: path)) != nil { removed += 1 }
        }
        ProfileConnectionCache().remove(forID: files.profileID)
        return removed
    }

    /// Выключает туннель и ждёт, пока iOS подтвердит отключение (до ~6 с):
    /// иначе расширение на остановке успело бы записать state заново.
    /// Подключение по требованию тоже снимаем — у свежей установки его нет.
    @MainActor
    static func stopTunnel(_ viewModel: ViewModel) async {
        if viewModel.connectOnDemand {
            viewModel.setConnectOnDemand(isEnabled: false)
        }
        guard viewModel.vpnDisplayState != .disconnected else { return }
        viewModel.performClose()
        for _ in 0..<30 where viewModel.vpnDisplayState != .disconnected {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }
}

#endif
