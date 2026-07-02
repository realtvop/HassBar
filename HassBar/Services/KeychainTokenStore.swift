//
//  KeychainTokenStore.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import Foundation
import Security

/// Boundary for persisting the Home Assistant Long-Lived Access Token.
/// Isolated behind a protocol so store logic can use an in-memory fake in tests.
nonisolated protocol KeychainTokenStoring: Sendable {
    func saveToken(_ token: String, for account: String) throws
    func loadToken(for account: String) -> String?
    func deleteToken(for account: String) throws
}

enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}

/// Keychain-backed implementation of `KeychainTokenStoring`.
nonisolated struct KeychainTokenStore: KeychainTokenStoring {
    let service: String

    init(service: String = "github.realtvop.HassBar") {
        self.service = service
    }

    func saveToken(_ token: String, for account: String) throws {
        let data = Data(token.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Replace any existing item to keep the API simple and idempotent.
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func loadToken(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteToken(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
