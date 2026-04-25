import Foundation
import Security

/// Keychain wrapper for the M9.A backup passphrase.
///
/// Shape of the secret: a single string per Keychain account. Multiple
/// accounts are supported (one per project, or a single shared one) so
/// callers can decide whether to share or partition. Storing the
/// passphrase here means the user types it once and the next backup is
/// silent — not stored in UserDefaults, not written to a file, not
/// recoverable without the macOS login keychain.
public protocol PassphraseStore: Sendable {
    func setPassphrase(_ passphrase: String, account: String) throws
    func getPassphrase(account: String) throws -> String?
    func deletePassphrase(account: String) throws
}

public enum PassphraseStoreError: Error, Equatable, Sendable {
    case keychainStatus(OSStatus)
    case decodeFailed
}

/// Production implementation backed by `kSecClassGenericPassword`.
public final class KeychainPassphraseStore: PassphraseStore, @unchecked Sendable {
    private let service: String

    /// `service` is the Keychain "service" string used to scope all
    /// passphrases. Defaults to ``"dev.kiln.backups"``; tests can pass a
    /// per-suite value to avoid colliding with the user's real entries.
    public init(service: String = "dev.kiln.backups") {
        self.service = service
    }

    public func setPassphrase(_ passphrase: String, account: String) throws {
        guard let data = passphrase.data(using: .utf8) else {
            throw PassphraseStoreError.decodeFailed
        }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Update if exists, add otherwise. Two-step is the common Keychain
        // recipe — `SecItemAdd` errors with `errSecDuplicateItem` if the
        // entry already exists.
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw PassphraseStoreError.keychainStatus(addStatus)
            }
            return
        }
        if updateStatus != errSecSuccess {
            throw PassphraseStoreError.keychainStatus(updateStatus)
        }
    }

    public func getPassphrase(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        if status != errSecSuccess {
            throw PassphraseStoreError.keychainStatus(status)
        }
        guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
            throw PassphraseStoreError.decodeFailed
        }
        return text
    }

    public func deletePassphrase(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw PassphraseStoreError.keychainStatus(status)
        }
    }
}

/// In-memory implementation for tests and SwiftUI previews. Thread-safe
/// via a serial-access lock so tests that exercise concurrent set/get
/// don't race.
public final class InMemoryPassphraseStore: PassphraseStore, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: String] = [:]

    public init() {}

    public func setPassphrase(_ passphrase: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        store[account] = passphrase
    }

    public func getPassphrase(account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return store[account]
    }

    public func deletePassphrase(account: String) throws {
        lock.lock(); defer { lock.unlock() }
        store.removeValue(forKey: account)
    }
}
