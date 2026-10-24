//
//  JetBoxNotifications.swift
//  JetBox
//
//  Разрешение на уведомления спрашиваем не при запуске (апстрим делал так —
//  клиент видел системный вопрос раньше, чем понимал, зачем), а когда защита
//  впервые включилась: уведомление приходит, если связь с домом прервалась
//  и нужна новая ссылка. Пауза — чтобы системный вопрос не закрыл анимацию
//  успеха щита.
//

import Foundation
import UserNotifications

enum JetBoxNotifications {
    static func requestIfNeeded(after delay: TimeInterval = 1.6) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let center = UNUserNotificationCenter.current()
            center.getNotificationSettings { settings in
                guard settings.authorizationStatus == .notDetermined else { return }
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error {
                        AppLogger.shared.log("JetBox: notification authorization error: \(error.localizedDescription)")
                    } else {
                        AppLogger.shared.log("JetBox: notification authorization granted: \(granted)")
                    }
                }
            }
        }
    }
}
