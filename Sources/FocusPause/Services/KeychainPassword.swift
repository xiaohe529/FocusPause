import Foundation
import Security

/// Per-app-friction password store backed by UserDefaults.
/// Not Keychain — this app is unsigned and Keychain prompts on every rebuild.
/// The password is not protecting secrets; it adds enough friction to prevent
/// impulse unblocking, which UserDefaults serves just fine.
enum KeychainPassword {
    private static let key = "lockPassword_v2"

    static func save(_ password: String) throws {
        UserDefaults.standard.set(password, forKey: key)
    }

    static func load() -> String? {
        if let fromUD = UserDefaults.standard.string(forKey: key), !fromUD.isEmpty {
            return fromUD
        }
        // One-shot migration from old Keychain-backed item
        if let fromKC = loadFromKeychain() {
            UserDefaults.standard.set(fromKC, forKey: key)
            deleteFromKeychain()
            return fromKC
        }
        return nil
    }

    static func verify(_ password: String) -> Bool {
        let stored = load()
        // Constant-time comparison
        guard let a = stored?.data(using: .utf8), let b = password.data(using: .utf8) else {
            return stored == password
        }
        guard a.count == b.count else { return false }
        var result: UInt8 = 0
        for i in 0..<a.count {
            result |= a[i] ^ b[i]
        }
        return result == 0
    }

    static func delete() {
        UserDefaults.standard.removeObject(forKey: key)
        deleteFromKeychain()
    }

    // MARK: - Legacy Keychain (one-shot migration)

    private static func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.focuspause.app",
            kSecAttrAccount as String: "lockPassword",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteFromKeychain() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.focuspause.app",
            kSecAttrAccount as String: "lockPassword"
        ] as CFDictionary)
    }
}