import Foundation

/// The eight card colours of «Настроить карты». Only the names live here; the gradients are
/// drawn by the app.
public enum FinanceCardTheme: String, CaseIterable, Codable, Sendable {
  case violet, indigo, plum, teal, graphite, rose, sand, forest

  /// The colour a card has until the owner picks one: accounts alternate violet and graphite
  /// (the second account is the dollar one), deposits indigo and plum, stocks teal. `cards`
  /// is in the default order, so the choice does not change when the owner reorders.
  public static func fallback(for card: FinanceCard, among cards: [FinanceCard]) -> FinanceCardTheme {
    let rank = cards.filter { $0.kind == card.kind }.firstIndex { $0.id == card.id } ?? 0
    switch card.kind {
    case .account: return rank % 2 == 0 ? .violet : .graphite
    case .deposit: return rank % 2 == 0 ? .indigo : .plum
    case .stocks: return .teal
    }
  }
}

/// The owner's card order and colours. It holds card ids and theme names only, never amounts.
public struct FinanceCardLayout: Codable, Equatable, Sendable {
  public var order: [String]
  /// Card id -> `FinanceCardTheme.rawValue`.
  public var themes: [String: String]

  public init(order: [String] = [], themes: [String: String] = [:]) {
    self.order = order
    self.themes = themes
  }

  /// Saved order first; new or unknown cards follow in their default order; ids of removed
  /// cards are ignored.
  public func ordered(_ cards: [FinanceCard]) -> [FinanceCard] {
    let byID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var seen = Set<String>()
    var result: [FinanceCard] = []
    for id in order {
      guard let card = byID[id], seen.insert(id).inserted else { continue }
      result.append(card)
    }
    for card in cards where seen.insert(card.id).inserted { result.append(card) }
    return result
  }

  /// The chosen theme, else the default one for the card's kind. `cards` is in default order.
  public func theme(for card: FinanceCard, among cards: [FinanceCard]) -> FinanceCardTheme {
    themes[card.id].flatMap(FinanceCardTheme.init(rawValue:))
      ?? FinanceCardTheme.fallback(for: card, among: cards)
  }

  public func resolvedThemes(for cards: [FinanceCard]) -> [String: FinanceCardTheme] {
    Dictionary(
      cards.map { ($0.id, theme(for: $0, among: cards)) }, uniquingKeysWith: { first, _ in first })
  }

  /// Moves one entry of `order`; `to` is the final index and is clamped to the list.
  public func moving(from: Int, to: Int) -> FinanceCardLayout {
    guard order.indices.contains(from) else { return self }
    var next = order
    let id = next.remove(at: from)
    next.insert(id, at: min(max(to, 0), next.count))
    return FinanceCardLayout(order: next, themes: themes)
  }

  public func setting(theme: FinanceCardTheme, for id: String) -> FinanceCardLayout {
    var next = themes
    next[id] = theme.rawValue
    return FinanceCardLayout(order: order, themes: next)
  }

  /// Drops order and theme entries of cards that no longer exist.
  public func pruned(to ids: [String]) -> FinanceCardLayout {
    let known = Set(ids)
    return FinanceCardLayout(
      order: order.filter { known.contains($0) }, themes: themes.filter { known.contains($0.key) })
  }

  /// A layout whose `order` lists exactly the current cards, so `moving` works on what the
  /// owner sees.
  public func aligned(to cards: [FinanceCard]) -> FinanceCardLayout {
    FinanceCardLayout(order: ordered(cards).map(\.id), themes: themes).pruned(to: cards.map(\.id))
  }
}
