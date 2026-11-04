import Foundation

/// GET /api/security: second-factor status and the signed-in devices.
public struct SecurityOverview: Decodable, Sendable, Equatable {
  public let totpEnabled: Bool
  public let recoveryCodesLeft: Int
  public let sessions: [SecuritySession]

  public init(totpEnabled: Bool, recoveryCodesLeft: Int, sessions: [SecuritySession]) {
    self.totpEnabled = totpEnabled
    self.recoveryCodesLeft = recoveryCodesLeft
    self.sessions = sessions
  }

  public var otherSessions: [SecuritySession] { sessions.filter { !$0.current } }
}

public struct SecuritySession: Decodable, Sendable, Equatable, Identifiable {
  public let id: String
  /// "web" or "ios"; anything else is shown as-is.
  public let client: String
  public let deviceName: String?
  public let createdAt: Date?
  public let lastSeenAt: Date?
  public let current: Bool

  public init(
    id: String, client: String, deviceName: String?, createdAt: Date?, lastSeenAt: Date?,
    current: Bool
  ) {
    self.id = id
    self.client = client
    self.deviceName = deviceName
    self.createdAt = createdAt
    self.lastSeenAt = lastSeenAt
    self.current = current
  }

  private enum Keys: String, CodingKey {
    case id, client, deviceName, createdAt, lastSeenAt, current
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    id = try c.decode(String.self, forKey: .id)
    client = try c.decodeIfPresent(String.self, forKey: .client) ?? "web"
    deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName)
    createdAt = Self.date(c, .createdAt)
    lastSeenAt = Self.date(c, .lastSeenAt)
    current = try c.decodeIfPresent(Bool.self, forKey: .current) ?? false
  }

  /// A session id goes into a URL path, so only plain token characters are accepted.
  public static func isValidID(_ id: String) -> Bool {
    (1...128).contains(id.utf8.count)
      && id.utf8.allSatisfy {
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45
          || $0 == 95
      }
  }

  /// ISO 8601 text (with or without fractions) or epoch seconds/milliseconds; unreadable is nil.
  private static func date(_ c: KeyedDecodingContainer<Keys>, _ key: Keys) -> Date? {
    if let text = try? c.decodeIfPresent(String.self, forKey: key) {
      let plain = ISO8601DateFormatter()
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return fractional.date(from: text) ?? plain.date(from: text)
    }
    if let number = try? c.decodeIfPresent(Double.self, forKey: key) {
      return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1000 : number)
    }
    return nil
  }
}

/// The device name sent at sign-in: the model only, never a personal name.
public enum DeviceLabel {
  public static let maxLength = 60

  /// «iPhone (iPhone14,5)»; just «iPhone» when the model is unknown.
  public static func make(model: String?) -> String {
    guard let model = model.flatMap(sanitized) else { return "iPhone" }
    return "iPhone (\(model))"
  }

  /// Printable text only, trimmed and capped; empty becomes nil.
  public static func sanitized(_ raw: String) -> String? {
    let cleaned = String(
      raw.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }.map(Character.init)
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return nil }
    return String(cleaned.prefix(maxLength))
  }
}
