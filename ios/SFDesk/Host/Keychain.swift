import Foundation
import Security

// The saved Salesforce login (refresh token) and the last signed-in user, in the Keychain.
enum Keychain {
  private static let service = "SF Desk Salesforce login"

  private static func query(_ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
  }

  static func save(_ data: Data, for account: String) {
    delete(account)
    var q = query(account)
    q[kSecValueData as String] = data
    #if os(iOS)
    q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    #endif
    SecItemAdd(q as CFDictionary, nil)
  }

  static func load(_ account: String) -> Data? {
    var q = query(account)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: CFTypeRef?
    return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
  }

  static func delete(_ account: String) {
    SecItemDelete(query(account) as CFDictionary)
  }
}
