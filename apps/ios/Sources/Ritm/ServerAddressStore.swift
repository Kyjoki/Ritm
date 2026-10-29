import Foundation
import RitmCore

/// The chosen Ritm server. Not a secret, so it lives in UserDefaults; anything unreadable or
/// invalid falls back to the default server.
enum ServerAddressStore {
  private static let key = "ritm.server.address"

  static func load() -> ServerAddress {
    guard let raw = UserDefaults.standard.string(forKey: key),
      case .success(let address) = ServerAddress.validate(raw)
    else { return .production }
    return address
  }

  static func save(_ address: ServerAddress) {
    if address == .production {
      UserDefaults.standard.removeObject(forKey: key)
    } else {
      UserDefaults.standard.set(address.origin, forKey: key)
    }
  }
}
