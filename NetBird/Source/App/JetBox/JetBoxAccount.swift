//
//  JetBoxAccount.swift
//  JetBox
//
//  «Delete account» (Apple 5.1.1(v), сборка 1.0 (14); спека
//  VPN_Box/docs/superpowers/specs/2026-11-22-app-account-delete-design.md).
//
//  Кабинет ничего физически не удаляет: снимает доступ всем устройствам
//  человека и закрывает ему вход по email. Приложение знает себя по токену
//  `app_token` из ответа verify. Токен живёт в Keychain «только это
//  устройство»: в бэкап на новый телефон он не уедет, там человек входит
//  по email заново.
//

import Foundation
import Security

/// Токен приложения из ответа verify.
enum JetBoxAppToken {
    static let service = "net.jetnet.jetbox.app-token"
    static let account = "current"

    static func load(service: String = service) -> String? {
        var query = baseQuery(service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return token
    }

    @discardableResult
    static func save(_ token: String, service: String = service) -> Bool {
        delete(service: service)
        guard !token.isEmpty else { return false }
        var item = baseQuery(service)
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess { AppLogger.shared.log("JetBox: токен приложения не сохранён (\(status))") }
        return status == errSecSuccess
    }

    static func delete(service: String = service) {
        SecItemDelete(baseQuery(service) as CFDictionary)
    }

    private static func baseQuery(_ service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

extension JetBoxLoginAPI {
    enum DeleteOutcome: Equatable {
        /// 200 — доступ снят; 401 — токен уже погашен (устройство отключено).
        /// В обоих случаях дальше локальный выход.
        case deleted
        case unauthorized
        /// 5xx, 429, нет сети — ничего не стираем, «попробуйте ещё раз».
        case failed
    }

    /// POST account/delete с `Authorization: Bearer <app_token>`.
    func deleteAccount(token: String) async -> DeleteOutcome {
        var request = URLRequest(url: base.appendingPathComponent("account/delete"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)
        do {
            let (_, response) = try await transport(request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            log("JetBox: удаление аккаунта — Кабинет ответил \(code)")
            switch code {
            case 200: return .deleted
            case 401: return .unauthorized
            default: return .failed
            }
        } catch {
            log("JetBox: удаление аккаунта — запрос не выполнен")
            return .failed
        }
    }

    /// `app_token` из ответа verify (в connect_url его нет — спека).
    static func appToken(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["app_token"] as? String, !token.isEmpty else { return nil }
        return token
    }
}
