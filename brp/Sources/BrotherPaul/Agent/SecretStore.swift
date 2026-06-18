import Foundation
import Security

enum SecretKey {
    static let anthropicAPIKey = "anthropic-api-key"
}

protocol SecretStore {
    func get(_ key: String) -> String?
    func set(_ value: String, for key: String)
    func delete(_ key: String)
}

/// Test-only in-memory store. Not thread-safe — fine for tests.
final class InMemorySecretStore: SecretStore {
    private var storage: [String: String] = [:]
    func get(_ key: String) -> String? { storage[key] }
    func set(_ value: String, for key: String) { storage[key] = value }
    func delete(_ key: String) { storage[key] = nil }
}

/// Generic-password Keychain store, scoped by service name.
final class KeychainSecretStore: SecretStore {
    private let service = "com.brotherpaul.secrets"

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    func set(_ value: String, for key: String) {
        delete(key)
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(q as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("BrotherPaul: keychain set failed for %@ (status %d)", key, Int(status))
        }
    }

    func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}
