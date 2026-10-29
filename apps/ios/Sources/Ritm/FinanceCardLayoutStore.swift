import Foundation
import Observation
import RitmCore

/// The owner's wallet order and card colours, kept on this device only. The server has no such
/// field, and the JSON holds card ids, their order and theme names, never an amount.
@MainActor @Observable
final class FinanceCardLayoutStore {
  private static let key = "ritm.finance.cardLayout.v1"

  private(set) var layout: FinanceCardLayout
  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.layout =
      defaults.data(forKey: Self.key)
      .flatMap { try? JSONDecoder().decode(FinanceCardLayout.self, from: $0) }
      ?? FinanceCardLayout()
  }

  /// `defaultCards` is the wallet in its default order.
  func ordered(_ defaultCards: [FinanceCard]) -> [FinanceCard] {
    layout.ordered(defaultCards)
  }

  func themes(for defaultCards: [FinanceCard]) -> [String: FinanceCardTheme] {
    layout.resolvedThemes(for: defaultCards)
  }

  /// SwiftUI `onMove` semantics: `offset` is the insertion point before the move.
  func move(fromOffsets source: IndexSet, toOffset offset: Int, in defaultCards: [FinanceCard]) {
    guard let from = source.first else { return }
    move(from: from, to: offset > from ? offset - 1 : offset, in: defaultCards)
  }

  /// `to` is the final index.
  func move(from: Int, to: Int, in defaultCards: [FinanceCard]) {
    update(layout.aligned(to: defaultCards).moving(from: from, to: to))
  }

  func setTheme(_ theme: FinanceCardTheme, for id: String, in defaultCards: [FinanceCard]) {
    update(layout.aligned(to: defaultCards).setting(theme: theme, for: id))
  }

  private func update(_ next: FinanceCardLayout) {
    guard next != layout else { return }
    layout = next
    if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: Self.key) }
  }
}
