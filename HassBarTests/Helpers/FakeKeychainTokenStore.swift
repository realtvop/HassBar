import Foundation
@testable import HassBar

final class FakeKeychainTokenStore: KeychainTokenStoring, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    func saveToken(_ token: String, for account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[account] = token
    }

    func loadToken(for account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[account]
    }

    func deleteToken(for account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[account] = nil
    }
}