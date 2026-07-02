//
//  AppConfig.swift
//  HassBar
//
//  Created by realtvop on 2026/6/28.
//

import Foundation

/// Persisted user configuration for HassBar.
///
/// `haURL`, `favorites`, and `entityAliases` live in `UserDefaults`; the access
/// token is kept in the Keychain via `KeychainTokenStoring`.
nonisolated final class AppConfig {
    private let defaults: UserDefaults
    let tokenStore: KeychainTokenStoring

    init(
        defaults: UserDefaults = .standard,
        tokenStore: KeychainTokenStoring = KeychainTokenStore()
    ) {
        self.defaults = defaults
        self.tokenStore = tokenStore
    }

    var haURL: String {
        get { defaults.string(forKey: Self.urlKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.urlKey) }
    }

    var favorites: Favorites {
        get {
            if let raw = defaults.string(forKey: Self.favoritesKey),
               let value = Favorites(rawValue: raw) {
                return value
            }
            return Favorites()
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.favoritesKey)
        }
    }

    var entityAliases: EntityAliases {
        get {
            if let raw = defaults.string(forKey: Self.entityAliasesKey),
               let value = EntityAliases(rawValue: raw) {
                return value
            }
            return EntityAliases()
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.entityAliasesKey)
        }
    }

    var entityIcons: EntityIcons {
        get {
            if let raw = defaults.string(forKey: Self.entityIconsKey),
               let value = EntityIcons(rawValue: raw) {
                return value
            }
            return EntityIcons()
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.entityIconsKey)
        }
    }

    var menuBarSensors: MenuBarSensors {
        get {
            if let raw = defaults.string(forKey: Self.menuBarSensorsKey),
               let value = MenuBarSensors(rawValue: raw) {
                return value
            }
            return MenuBarSensors()
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.menuBarSensorsKey)
        }
    }

    var token: String? {
        tokenStore.loadToken(for: Self.tokenAccount)
    }

    func saveToken(_ token: String) throws {
        try tokenStore.saveToken(token, for: Self.tokenAccount)
    }

    func clearToken() {
        try? tokenStore.deleteToken(for: Self.tokenAccount)
    }

    /// True when both a URL and a token are available, ready to talk to HA.
    var isConfigured: Bool {
        let url = haURL
        guard !url.isEmpty, let scheme = URL(string: url)?.scheme, let host = URL(string: url)?.host, !host.isEmpty else {
            return false
        }
        _ = scheme
        return (token ?? "").isEmpty == false
    }

    static let urlKey = "ha.baseURL"
    static let favoritesKey = "ha.favorites"
    static let entityAliasesKey = "ha.entityAliases"
    static let entityIconsKey = "ha.entityIcons"
    static let menuBarSensorsKey = "ha.menuBarSensors"
    static let tokenAccount = "long-lived-access-token"
}
