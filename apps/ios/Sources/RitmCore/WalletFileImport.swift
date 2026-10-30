import Foundation

// The «without opening the app» mode: the Shortcuts «Транзакция» automation appends one line per
// payment to `purchases.txt` in a Files folder, and Ritm reads that file when it is opened. A line
// is the same link text as the URL-scheme mode, written raw by Shortcuts (spaces, Cyrillic, commas
// are not percent-encoded), or just its query string. The file is only ever read.

public enum WalletFileImport {
  public static let fileName = "purchases.txt"
  /// Only the newest lines count; the file is never rewritten, so it only grows.
  public static let maxLines = 500
  public static let maxLineLength = 1000

  /// One purchase per usable line, in file order (oldest first). The same id counts once: a line
  /// that carries a time (`at=`) twice is one purchase. Byte-identical lines WITHOUT any time are
  /// separate purchases (the n-th copy gets its own id), because two coffees at the same price on
  /// one day look exactly alike and a lost purchase is worse than an extra one. `skipped`
  /// counts non-empty lines that are not a purchase: garbage, a wrong link, a line that is too long.
  public static func parse(
    text: String, today: String, receivedAt: String
  ) -> (purchases: [WalletPurchase], skipped: Int) {
    let lines = Array(significantLines(text).suffix(maxLines))
    var purchases: [WalletPurchase] = []
    var seen = Set<String>()
    var skipped = 0
    var copies: [String: Int] = [:]
    for line in lines {
      let occurrence = copies[line, default: 0]
      copies[line] = occurrence + 1
      guard line.count <= maxLineLength,
        let purchase = purchase(
          from: line, today: today, receivedAt: receivedAt, occurrence: occurrence)
      else {
        skipped += 1
        continue
      }
      if seen.insert(purchase.id).inserted { purchases.append(purchase) }
    }
    return (purchases, skipped)
  }

  // MARK: - Private

  private static let trimmed: CharacterSet = {
    var set = CharacterSet.whitespacesAndNewlines
    set.insert("\u{FEFF}")
    return set
  }()

  /// Non-empty lines for LF, CRLF and lone CR line ends, trimmed (also of a BOM).
  private static func significantLines(_ text: String) -> [String] {
    text.components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: trimmed) }
      .filter { !$0.isEmpty }
  }

  private static func purchase(
    from line: String, today: String, receivedAt: String, occurrence: Int
  ) -> WalletPurchase? {
    guard let url = linkURL(for: line) else { return nil }
    if case .success(let purchase) = WalletLink.parse(
      url, today: today, receivedAt: receivedAt, occurrence: occurrence)
    {
      return purchase
    }
    return nil
  }

  /// A `ritm://add?…` line or a bare `amount=…&merchant=…` query becomes a real URL.
  private static func linkURL(for line: String) -> URL? {
    let text: String
    if line.lowercased().hasPrefix("\(WalletLink.scheme):") {
      text = line
    } else if line.contains("://") || !line.contains("=") {
      return nil
    } else {
      text = "\(WalletLink.scheme)://add?" + (line.hasPrefix("?") ? String(line.dropFirst()) : line)
    }
    return URL(string: percentEncoded(text))
  }

  private static let keptBytes: Set<UInt8> = Set(
    Array(
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@/?".utf8))

  /// Shortcuts writes the variables raw. Encodes what is not allowed in a URL and keeps `%XX`
  /// sequences and the structural characters (`? & = +`) as they are.
  static func percentEncoded(_ text: String) -> String {
    let bytes = Array(text.utf8)
    var result = ""
    var index = 0
    while index < bytes.count {
      let byte = bytes[index]
      if keptBytes.contains(byte) {
        result.append(Character(UnicodeScalar(byte)))
      } else if byte == 0x25, index + 2 < bytes.count, isHex(bytes[index + 1]),
        isHex(bytes[index + 2])
      {
        result.append("%")
      } else {
        result.append(String(format: "%%%02X", byte))
      }
      index += 1
    }
    return result
  }

  private static func isHex(_ byte: UInt8) -> Bool {
    (0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)
  }
}

// MARK: - Into the inbox

extension WalletState {
  /// Result of putting a whole file into the inbox.
  public struct FileReceipt: Equatable, Sendable {
    public var added = 0
    /// Already pending, confirmed or skipped earlier.
    public var duplicates = 0
    /// New purchases that did not fit because the inbox is full; they stay in the file.
    public var overflow = 0
  }

  /// Adds purchases in order (the newest ends on top). Never drops a pending purchase to make
  /// room: when the inbox is full, new ones are counted in `overflow` and left for the next read.
  public func receiving(file purchases: [WalletPurchase]) -> (state: WalletState, receipt: FileReceipt)
  {
    var next = self
    var receipt = FileReceipt()
    for purchase in purchases {
      let result = next.receiving(purchase)
      guard result.added else {
        receipt.duplicates += 1
        continue
      }
      if next.pending.count >= WalletInbox.capacity {
        receipt.overflow += 1
        continue
      }
      next = result.state
      receipt.added += 1
    }
    return (next, receipt)
  }
}
