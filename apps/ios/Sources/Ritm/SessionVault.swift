import Foundation
import RitmCore
import Security

/// Stores only this device's revocable session. Passwords are never persisted.
struct SessionVault {
  private let service = "app.ritm.personal.session"
  private let account = "ritm-eta-hazel.vercel.app"
  // A non-secret tombstone prevents restoring a logged-out session even if Keychain
  // deletion temporarily fails (for example while the device is locked).
  private let disabledKey = "ritm.session.restoreDisabled"

  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: false,
    ]
  }

  func load() throws -> SessionCredential? {
    guard !UserDefaults.standard.bool(forKey: disabledKey) else { return nil }
    var attributes = query
    attributes[kSecReturnData as String] = true
    attributes[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(attributes as CFDictionary, &result)
    guard status != errSecItemNotFound else { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw VaultError.status(status)
    }
    do {
      let credential = try JSONDecoder().decode(SessionCredential.self, from: data)
      guard credential.expires > Date() else {
        try delete()
        return nil
      }
      return credential
    } catch {
      try delete()
      return nil
    }
  }

  func save(_ credential: SessionCredential) throws {
    let data = try JSONEncoder().encode(credential)
    let values: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
    if status == errSecItemNotFound {
      var attributes = query
      values.forEach { attributes[$0.key] = $0.value }
      let insertion = SecItemAdd(attributes as CFDictionary, nil)
      guard insertion == errSecSuccess else { throw VaultError.status(insertion) }
    } else if status != errSecSuccess {
      throw VaultError.status(status)
    }
    UserDefaults.standard.set(false, forKey: disabledKey)
  }

  func delete() throws {
    UserDefaults.standard.set(true, forKey: disabledKey)
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw VaultError.status(status)
    }
  }

  enum VaultError: Error { case status(OSStatus) }
}
