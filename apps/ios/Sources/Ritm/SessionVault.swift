import Foundation
import RitmCore
import Security

/// Stores this device's revocable session credential (never the password) in the Keychain,
/// this device only.
struct SessionVault {
  private let service = "app.ritm.personal.session"
  /// Keychain account = the server (host[:port]). A session is only ever read for, and so sent
  /// to, the server it was created on.
  private let account: String
  // A non-secret tombstone prevents restoring a logged-out session even if Keychain
  // deletion temporarily fails (for example while the device is locked).
  private let disabledKey: String

  init(server: ServerAddress) {
    account = server.account
    // The default server keeps the original key so an existing tombstone still applies.
    disabledKey =
      server == .production
      ? "ritm.session.restoreDisabled" : "ritm.session.restoreDisabled." + server.account
  }

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

  // MARK: Legacy saved sign-in

  /// Earlier builds kept the owner's login and password here to sign in again by themselves.
  /// The password is no longer stored anywhere: this removes any such item for every server.
  static func purgeLegacySavedLogin() {
    SecItemDelete(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "app.ritm.personal.login",
      ] as CFDictionary)
  }
}
