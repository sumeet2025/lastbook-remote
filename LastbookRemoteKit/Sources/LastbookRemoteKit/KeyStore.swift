import Foundation
#if canImport(Security)
import Security
#endif

/// Where access keys live. The app uses `KeychainKeyStore`; tests use `MemoryKeyStore`.
public protocol KeyStore: Sendable {
    func key(for server: UUID) -> String?
    func setKey(_ key: String, for server: UUID) throws
    func removeKey(for server: UUID)
}

public final class MemoryKeyStore: KeyStore, @unchecked Sendable {
    private var keys: [UUID: String] = [:]
    private let lock = NSLock()
    public init() {}
    public func key(for server: UUID) -> String? { lock.lock(); defer { lock.unlock() }; return keys[server] }
    public func setKey(_ key: String, for server: UUID) throws { lock.lock(); keys[server] = key; lock.unlock() }
    public func removeKey(for server: UUID) { lock.lock(); keys[server] = nil; lock.unlock() }
}

#if canImport(Security)
/// Access keys as generic-password items, readable only while this device is unlocked
/// and never synced or restored to another device.
public struct KeychainKeyStore: KeyStore {
    public let service: String

    public init(service: String = "org.lastbook.remote.access-key") {
        self.service = service
    }

    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    public func key(for server: UUID) -> String? {
        var q = query(server)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setKey(_ key: String, for server: UUID) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query(server) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(server)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let s = SecItemAdd(add as CFDictionary, nil)
            guard s == errSecSuccess else { throw KeychainError(status: s) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func removeKey(for server: UUID) {
        SecItemDelete(query(server) as CFDictionary)
    }
}

public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? { "The access key could not be saved in the Keychain (\(status))." }
}
#endif
