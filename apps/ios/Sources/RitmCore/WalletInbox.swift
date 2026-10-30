import Foundation

// Apple Pay purchases reach the app through an iOS Shortcuts «Transaction» automation that opens
// `ritm://add?amount=…&merchant=…&card=…&date=…`. Each purchase waits in a pending inbox with a
// category suggested from what the owner chose before for the same merchant; the owner confirms.

/// One purchase received from Shortcuts and not yet confirmed. Never holds more than the last four
/// card digits.
public struct WalletPurchase: Codable, Equatable, Identifiable, Sendable {
  /// Stable dedupe key, see `makeID`.
  public let id: String
  /// As received: trimmed, spaces collapsed, at most 80 characters.
  public let merchant: String
  /// Integer hundredths, always > 0.
  public let amountMinor: Int
  public let currency: FinanceCurrency
  /// A masked «•••• 1234» label or a short card name.
  public let card: String?
  /// YYYY-MM-DD.
  public let date: String
  /// ISO-8601 UTC, injected by the caller.
  public let receivedAt: String
  /// Russian label from `FinanceCategories.expense`, or nil.
  public var suggestedCategory: String?

  public init(
    id: String, merchant: String, amountMinor: Int, currency: FinanceCurrency,
    card: String? = nil, date: String, receivedAt: String, suggestedCategory: String? = nil
  ) {
    self.id = id
    self.merchant = merchant
    self.amountMinor = amountMinor
    self.currency = currency
    self.card = card
    self.date = date
    self.receivedAt = receivedAt
    self.suggestedCategory = suggestedCategory
  }

  /// Deterministic across launches (FNV-1a, not `Hasher`): the same purchase always gets the same id.
  public static func makeID(
    date: String, amountMinor: Int, currency: FinanceCurrency, merchant: String, card: String?
  ) -> String {
    let normalised = MerchantMemory.normalise(merchant)
    let name = normalised.isEmpty ? merchant.lowercased() : normalised
    let source = [date, String(amountMinor), currency.rawValue, name, card ?? ""]
      .joined(separator: "\u{1F}")
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in source.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01b3
    }
    let hex = String(hash, radix: 16)
    return "w" + String(repeating: "0", count: 16 - hex.count) + hex
  }
}

public enum WalletLinkError: Error, Equatable, Sendable {
  case wrongScheme, wrongAction, missingAmount, invalidAmount, missingMerchant, tooLarge
}

public enum WalletLink {
  public static let scheme = "ritm"
  public static let maxMerchantLength = 80
  public static let maxCardLength = 40
  static let maxURLLength = 4096

  public static func parse(
    _ url: URL, today: String, receivedAt: String
  ) -> Result<WalletPurchase, WalletLinkError> {
    guard url.scheme?.lowercased() == scheme else { return .failure(.wrongScheme) }
    guard url.absoluteString.count <= maxURLLength else { return .failure(.tooLarge) }
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      isAddAction(components)
    else { return .failure(.wrongAction) }
    let items = components.percentEncodedQueryItems ?? []

    guard let rawAmount = value(of: "amount", in: items),
      !rawAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return .failure(.missingAmount) }
    let amount: (minor: Int, currency: FinanceCurrency)
    switch WalletAmount.parse(rawAmount, defaultCurrency: .KZT) {
    case .success(let parsed): amount = parsed
    case .failure(let error): return .failure(error)
    }

    let merchant = WalletText.clean(value(of: "merchant", in: items) ?? "", limit: maxMerchantLength)
    guard !merchant.isEmpty else { return .failure(.missingMerchant) }

    let card = cardLabel(value(of: "card", in: items))
    let date = value(of: "date", in: items).flatMap(WalletDate.normalise) ?? today
    let id = WalletPurchase.makeID(
      date: date, amountMinor: amount.minor, currency: amount.currency, merchant: merchant,
      card: card)
    return .success(
      WalletPurchase(
        id: id, merchant: merchant, amountMinor: amount.minor, currency: amount.currency,
        card: card, date: date, receivedAt: receivedAt))
  }

  /// The text the owner pastes into the Shortcuts «Open URL» action. The placeholders are the
  /// Shortcuts variables of the «Transaction» automation; the same in every language.
  public static func template(language: Language) -> String {
    "\(scheme)://add?amount=<Amount>&merchant=<Merchant>&card=<Card>&date=<Date>"
  }

  /// Amount as Shortcuts may format it; the sign is ignored. Nil for zero, garbage or an amount
  /// above the finance limit.
  public static func parseAmount(
    _ text: String, defaultCurrency: FinanceCurrency
  ) -> (minor: Int, currency: FinanceCurrency)? {
    if case .success(let parsed) = WalletAmount.parse(text, defaultCurrency: defaultCurrency) {
      return parsed
    }
    return nil
  }

  // MARK: - Private

  private static func isAddAction(_ components: URLComponents) -> Bool {
    if let host = components.host, !host.isEmpty { return host.lowercased() == "add" }
    return components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
      == "add"
  }

  /// First value of the query item, decoded. A raw `+` is a space; an encoded `%2B` stays `+`.
  private static func value(of name: String, in items: [URLQueryItem]) -> String? {
    guard let raw = items.first(where: { $0.name.lowercased() == name })?.value else { return nil }
    return raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
  }

  /// Four or more digits anywhere: keep only «•••• 1234». Otherwise the trimmed card name.
  private static func cardLabel(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let digits = raw.filter { $0.isASCII && $0.isNumber }
    if digits.count >= 4 { return "•••• " + digits.suffix(4) }
    let name = WalletText.clean(raw, limit: maxCardLength)
    return name.isEmpty ? nil : name
  }
}

/// Builds the expense the server receives once the owner confirms a pending purchase.
public enum WalletEntryBuilder {
  static let notePrefix = "Apple Pay · "
  static let maxNoteLength = 400

  public static func expense(from purchase: WalletPurchase, category: String) -> FinanceEntryInput {
    let note = String((notePrefix + purchase.merchant).prefix(maxNoteLength))
    return FinanceEntryInput(
      type: .expense, currency: purchase.currency, note: note, amountMinor: purchase.amountMinor,
      date: purchase.date, category: category)
  }
}

// MARK: - Merchant memory

/// What category the owner chose for a merchant before, keyed by the normalised merchant name.
public struct MerchantMemory: Codable, Equatable, Sendable {
  public static let maxMerchants = 500

  struct Stat: Codable, Equatable, Sendable {
    var count: Int
    var last: String
  }

  /// normalised merchant → category → how often and when it was last used.
  private var merchants: [String: [String: Stat]]

  public init() { merchants = [:] }

  public var merchantCount: Int { merchants.count }

  private static let countryCodes: Set<String> = [
    "kz", "kaz", "us", "usa", "ru", "rus", "ae", "are", "tr", "tur", "gb", "gbr", "uz", "kg",
    "cn", "deu", "fra",
  ]
  private static let cities: Set<String> = [
    "almaty", "astana", "shymkent", "karaganda", "aktau", "atyrau", "aktobe", "pavlodar",
    "semey", "kostanay", "taraz", "turkestan", "moscow", "dubai", "istanbul", "antalya",
    "london", "paris", "berlin", "алматы", "астана", "шымкент", "караганда", "москва",
  ]
  private static let maxKeyLength = 60

  public static func normalise(_ merchant: String) -> String {
    var cleaned = ""
    for character in merchant.lowercased() {
      if character == "'" || character == "’" || character == "`" { continue }
      cleaned.append(character.isLetter || character.isNumber ? character : " ")
    }
    var tokens = cleaned.split(separator: " ").map(String.init).filter { !isNoise($0) }
    while tokens.count > 1, let last = tokens.last,
      countryCodes.contains(last) || cities.contains(last)
    {
      tokens.removeLast()
    }
    return String(tokens.joined(separator: " ").prefix(maxKeyLength))
  }

  /// Digits-only tokens and terminal ids such as «ts01234».
  private static func isNoise(_ token: String) -> Bool {
    let digits = token.filter(\.isNumber).count
    return digits == token.count || digits >= 3
  }

  public func learning(merchant: String, category: String, at: String) -> MerchantMemory {
    let key = MerchantMemory.normalise(merchant)
    let label = category.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty, !label.isEmpty else { return self }
    var copy = self
    var stats = merchants[key] ?? [:]
    let previous = stats[label]
    stats[label] = Stat(count: (previous?.count ?? 0) + 1, last: max(previous?.last ?? "", at))
    copy.merchants[key] = stats
    copy.evictOldest(keeping: key)
    return copy
  }

  public func suggest(merchant: String) -> String? {
    let key = MerchantMemory.normalise(merchant)
    guard !key.isEmpty else { return nil }
    if let stats = merchants[key] { return MerchantMemory.ranked(stats).first?.key }
    guard let head = MerchantMemory.head(of: key) else { return nil }
    var merged: [String: Stat] = [:]
    for (other, stats) in merchants where MerchantMemory.head(of: other) == head {
      for (label, stat) in stats {
        let old = merged[label]
        merged[label] = Stat(
          count: (old?.count ?? 0) + stat.count, last: max(old?.last ?? "", stat.last))
      }
    }
    let ranked = MerchantMemory.ranked(merged)
    guard let top = ranked.first else { return nil }
    if ranked.count > 1, ranked[1].value.count == top.value.count { return nil }
    return top.key
  }

  public func forgetting(merchant: String) -> MerchantMemory {
    var copy = self
    copy.merchants[MerchantMemory.normalise(merchant)] = nil
    return copy
  }

  // MARK: - Private

  /// The first two tokens; nil for a single-token name, which only matches exactly.
  private static func head(of key: String) -> String? {
    let tokens = key.split(separator: " ")
    return tokens.count >= 2 ? tokens[0] + " " + tokens[1] : nil
  }

  /// Most frequent first; ties → most recent, then label for a stable order.
  private static func ranked(_ stats: [String: Stat]) -> [(key: String, value: Stat)] {
    stats.sorted {
      if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
      if $0.value.last != $1.value.last { return $0.value.last > $1.value.last }
      return $0.key < $1.key
    }
  }

  private mutating func evictOldest(keeping key: String) {
    let excess = merchants.count - MerchantMemory.maxMerchants
    guard excess > 0 else { return }
    let oldest = merchants.filter { $0.key != key }
      .map { (key: $0.key, last: $0.value.values.map(\.last).max() ?? "") }
      .sorted { ($0.last, $0.key) < ($1.last, $1.key) }
      .prefix(excess)
    for entry in oldest { merchants[entry.key] = nil }
  }
}

// MARK: - Inbox

/// Purchases waiting for the owner's confirmation, newest first.
public struct WalletInbox: Codable, Equatable, Sendable {
  public static let capacity = 50

  public private(set) var pending: [WalletPurchase]

  public init() { pending = [] }

  /// Ignores a purchase already pending or in `knownIDs` (confirmed or skipped earlier).
  public func adding(
    _ purchase: WalletPurchase, memory: MerchantMemory, knownIDs: Set<String>
  ) -> (inbox: WalletInbox, added: Bool) {
    guard !knownIDs.contains(purchase.id), !pending.contains(where: { $0.id == purchase.id })
    else { return (self, false) }
    var item = purchase
    if item.suggestedCategory == nil, let suggestion = memory.suggest(merchant: purchase.merchant),
      FinanceCategories.expense.contains(where: { $0.label == suggestion })
    {
      item.suggestedCategory = suggestion
    }
    var copy = self
    copy.pending = Array(([item] + pending).prefix(WalletInbox.capacity))
    return (copy, true)
  }

  public func removing(id: String) -> WalletInbox {
    var copy = self
    copy.pending = pending.filter { $0.id != id }
    return copy
  }

  public func settingCategory(_ category: String, for id: String) -> WalletInbox {
    var copy = self
    copy.pending = pending.map {
      guard $0.id == id else { return $0 }
      var item = $0
      item.suggestedCategory = category
      return item
    }
    return copy
  }
}

// MARK: - Parsing helpers

enum WalletText {
  /// Control characters and line breaks become spaces, runs of spaces collapse, then trim and cut.
  static func clean(_ text: String, limit: Int) -> String {
    var result = ""
    var pendingSpace = false
    for character in text {
      let isControl = character.unicodeScalars.allSatisfy {
        $0.properties.generalCategory == .control
      }
      if character.isWhitespace || isControl {
        pendingSpace = !result.isEmpty
      } else {
        if pendingSpace { result.append(" ") }
        pendingSpace = false
        result.append(character)
      }
    }
    return String(result.prefix(limit)).trimmingCharacters(in: .whitespaces)
  }
}

enum WalletDate {
  /// `YYYY-MM-DD…` (also an ISO timestamp) or `DD.MM.YYYY` / `DD/MM/YYYY` → `YYYY-MM-DD`; nil if
  /// it is not a real calendar date.
  static func normalise(_ text: String) -> String? {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let match = value.range(of: #"^\d{4}-\d{2}-\d{2}(?!\d)"#, options: .regularExpression) {
      let parts = value[match].split(separator: "-").compactMap { Int($0) }
      return parts.count == 3 ? format(year: parts[0], month: parts[1], day: parts[2]) : nil
    }
    if let match = value.range(
      of: #"^\d{1,2}[./]\d{1,2}[./]\d{4}(?!\d)"#, options: .regularExpression)
    {
      let parts = value[match].split(whereSeparator: { $0 == "." || $0 == "/" }).compactMap {
        Int($0)
      }
      return parts.count == 3 ? format(year: parts[2], month: parts[1], day: parts[0]) : nil
    }
    return nil
  }

  private static func format(year: Int, month: Int, day: Int) -> String? {
    guard (2000...2100).contains(year), (1...12).contains(month), day >= 1,
      day <= daysIn(month: month, year: year)
    else { return nil }
    return String(format: "%04d-%02d-%02d", year, month, day)
  }

  private static func daysIn(month: Int, year: Int) -> Int {
    switch month {
    case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
    case 4, 6, 9, 11: return 30
    default: return 31
    }
  }
}

enum WalletAmount {
  static let maxMinor = 1_000_000_000_000

  private static let currencyMarks: [String: FinanceCurrency] = [
    "₸": .KZT, "KZT": .KZT, "KZ₸": .KZT, "ТГ": .KZT, "ТЕНГЕ": .KZT,
    "$": .USD, "USD": .USD, "US$": .USD,
    "€": .EUR, "EUR": .EUR,
    "₽": .RUB, "RUB": .RUB, "RUR": .RUB, "РУБ": .RUB,
  ]

  static func parse(
    _ text: String, defaultCurrency: FinanceCurrency
  ) -> Result<(minor: Int, currency: FinanceCurrency), WalletLinkError> {
    guard let scanned = scan(text) else { return .failure(.invalidAmount) }
    var currency: FinanceCurrency?
    for run in scanned.marks {
      guard let known = currencyMarks[run.uppercased()] else { return .failure(.invalidAmount) }
      if let currency, currency != known { return .failure(.invalidAmount) }
      currency = known
    }
    guard let (integer, fraction) = split(scanned.number) else { return .failure(.invalidAmount) }
    guard integer.count <= 13 else { return .failure(.tooLarge) }
    let units = Int(integer) ?? 0
    let cents = Int(fraction.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
    let minor = units * 100 + cents
    if minor == 0 { return .failure(.invalidAmount) }
    if minor > maxMinor { return .failure(.tooLarge) }
    return .success((minor, currency ?? defaultCurrency))
  }

  /// Separates the numeric part (digits, `.`, `,` and single spaces between digits) from currency
  /// marks. Signs before the number are ignored; a `+` counts as a space (URL-encoded blank).
  private static func scan(_ text: String) -> (number: String, marks: [String])? {
    var number = ""
    var marks: [String] = []
    var run = ""
    var started = false
    var markAfterDigits = false
    func flush() {
      guard !run.isEmpty else { return }
      marks.append(run)
      if started { markAfterDigits = true }
      run = ""
    }
    for character in text {
      if character.isASCII && character.isNumber {
        flush()
        if markAfterDigits { return nil }
        number.append(character)
        started = true
      } else if character == "." || character == "," {
        flush()
        number.append(character)
      } else if character.isWhitespace || character == "+" {
        flush()
        if started && number.last != " " { number.append(" ") }
      } else if character == "-" || character == "−" || character == "–" {
        flush()
        if started { return nil }
      } else {
        run.append(character)
      }
    }
    flush()
    while let last = number.last, last == " " || last == "." || last == "," {
      number.removeLast()
    }
    return number.isEmpty ? nil : (number, marks)
  }

  /// Integer digits and fraction digits (at most two), or nil when the grouping is not valid.
  private static func split(_ number: String) -> (String, String)? {
    let characters = Array(number)
    let dot = characters.lastIndex(of: ".")
    let comma = characters.lastIndex(of: ",")
    var decimalIndex: Int?
    switch (dot, comma) {
    case (let d?, let c?):
      decimalIndex = max(d, c)
    case (let index?, nil), (nil, let index?):
      let mark = characters[index]
      let digitsAfter = characters.count - index - 1
      let before = characters[..<index].filter { $0.isNumber }
      let isGrouping =
        characters.filter { $0 == mark }.count > 1
        || (digitsAfter == 3 && (1...3).contains(before.count) && before.first != "0"
          && !characters[..<index].contains(" "))
      decimalIndex = isGrouping ? nil : index
    default:
      decimalIndex = nil
    }
    let integerPart = decimalIndex.map { String(characters[..<$0]) } ?? number
    let fraction = decimalIndex.map { String(characters[($0 + 1)...]) } ?? ""
    guard fraction.count <= 2, fraction.allSatisfy({ $0.isASCII && $0.isNumber }) else {
      return nil
    }
    guard let integer = digits(ofGrouped: integerPart) else { return nil }
    return (integer, fraction)
  }

  /// «1 234 567», «1,234,567» or «1234567» → digits; one kind of separator, groups of three.
  private static func digits(ofGrouped text: String) -> String? {
    if text.isEmpty { return "" }
    let separators = Set(text.filter { !$0.isNumber })
    if separators.isEmpty { return text }
    guard separators.count == 1, let separator = separators.first else { return nil }
    let groups = text.split(separator: separator, omittingEmptySubsequences: false)
    guard let first = groups.first, (1...3).contains(first.count),
      groups.dropFirst().allSatisfy({ $0.count == 3 })
    else { return nil }
    return groups.joined()
  }
}
