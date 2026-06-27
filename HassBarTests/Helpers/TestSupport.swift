import Foundation
@testable import HassBar

enum TestSupport {
    /// AppConfig backed by an ephemeral UserDefaults suite + in-memory keychain,
    /// so tests never touch real system storage.
    static func makeConfig() -> AppConfig {
        let suite = "HassBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppConfig(defaults: defaults, tokenStore: FakeKeychainTokenStore())
    }
}