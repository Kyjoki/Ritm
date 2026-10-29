import Foundation

public enum ServerAddressError: Error, Sendable, Equatable, LocalizedError {
  case empty
  case notHTTPS
  case hasCredentials
  case hasQueryOrFragment
  case hasPath
  case invalidHost
  case invalidPort

  public var errorDescription: String? {
    switch self {
    case .empty: "Введите адрес сервера."
    case .notHTTPS: "Нужен защищённый адрес, который начинается с https://."
    case .hasCredentials: "В адресе не должно быть логина и пароля."
    case .hasQueryOrFragment: "Уберите из адреса всё после знака ? или #."
    case .hasPath: "Укажите только адрес сервера, без пути после него."
    case .invalidHost: "Не удалось разобрать адрес. Пример: https://laptop.tailnet.ts.net"
    case .invalidPort: "Порт в адресе должен быть числом от 1 до 65535."
    }
  }
}

/// The only place that decides which servers the app may talk to: an https origin with a host
/// and an optional port. No credentials, path, query or fragment, so a session cookie and the
/// Origin header can never be tied to anything but this exact origin.
public struct ServerAddress: Equatable, Sendable, CustomStringConvertible {
  private static let defaultPort = 443
  private static let maxHostLength = 253

  public static let production = ServerAddress(host: "ritm-eta-hazel.vercel.app", port: nil)

  /// Lower-case ASCII host name (IPv6 literals are not accepted).
  public let host: String
  /// Nil for the standard https port.
  public let port: Int?

  private init(host: String, port: Int?) {
    self.host = host
    self.port = port
  }

  /// `https://host[:port]` with no trailing slash; also the exact Origin header value.
  public var origin: String {
    "https://" + host + (port.map { ":\($0)" } ?? "")
  }

  public var url: URL { URL(string: origin)! }

  /// Keychain account: one session and saved login per server, never shared between servers.
  public var account: String { host + (port.map { ":\($0)" } ?? "") }

  public var description: String { origin }

  /// Accepts `host`, `host:port` and `https://host[:port][/]`; everything else is refused.
  public static func validate(_ raw: String) -> Result<ServerAddress, ServerAddressError> {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return .failure(.empty) }
    guard text.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value != 127 }) else {
      return .failure(.invalidHost)
    }
    var rest = Substring(text)
    if let separator = text.range(of: "://") {
      let scheme = text[..<separator.lowerBound]
      guard scheme.lowercased() == "https" else {
        return .failure(scheme.isEmpty ? .invalidHost : .notHTTPS)
      }
      rest = text[separator.upperBound...]
    }
    if rest.contains("@") { return .failure(.hasCredentials) }
    if rest.contains("?") || rest.contains("#") { return .failure(.hasQueryOrFragment) }
    var authority = rest
    if let slash = rest.firstIndex(of: "/") {
      authority = rest[..<slash]
      guard rest[slash...] == "/" else { return .failure(.hasPath) }
    }
    guard !authority.contains("[") && !authority.contains("]") else {
      return .failure(.invalidHost)  // IPv6 literals have no valid certificate and are not supported.
    }
    var hostText = authority
    var port: Int?
    if let colon = authority.lastIndex(of: ":") {
      hostText = authority[..<colon]
      let digits = authority[authority.index(after: colon)...]
      guard !digits.isEmpty, digits.utf8.count <= 5, digits.allSatisfy(\.isASCIIDigit),
        let value = Int(digits), (1...65535).contains(value)
      else { return .failure(.invalidPort) }
      port = value == defaultPort ? nil : value
    }
    let host = hostText.lowercased()
    guard isValidHost(host) else { return .failure(.invalidHost) }
    return .success(ServerAddress(host: host, port: port))
  }

  private static func isValidHost(_ host: String) -> Bool {
    guard !host.isEmpty, host.utf8.count <= maxHostLength else { return false }
    return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
      !label.isEmpty && label.utf8.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
        && label.utf8.allSatisfy { byte in
          (97...122).contains(byte) || (48...57).contains(byte) || byte == 45
        }
    }
  }
}

extension Character {
  fileprivate var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
