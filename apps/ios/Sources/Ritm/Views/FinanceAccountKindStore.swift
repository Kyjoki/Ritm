import Foundation
import Observation

/// The server keeps every extra account as a `deposit` entry. The owner calls some of them
/// «Счёт» and some «Депозит»; that choice has no server field, so it is remembered on this
/// device: entry id -> «plain account». A `deposit` entry without a flag counts as «Депозит».
@MainActor
@Observable
final class FinanceAccountKindStore {
  private static let key = "ritm.finance.accountKinds.v1"

  private(set) var plain: Set<String>
  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.plain = Set(defaults.stringArray(forKey: Self.key) ?? [])
  }

  /// True for an entry the owner created or edited as «Счёт».
  func isPlain(_ id: String) -> Bool { plain.contains(id) }

  func set(plain isPlain: Bool, for id: String) {
    var next = plain
    if isPlain { next.insert(id) } else { next.remove(id) }
    save(next)
  }

  func remove(_ id: String) { set(plain: false, for: id) }

  /// «Сбросить финансы»: forget every flag.
  func clear() {
    defaults.removeObject(forKey: Self.key)
    plain = []
  }

  private func save(_ next: Set<String>) {
    guard next != plain else { return }
    plain = next
    defaults.set(Array(next).sorted(), forKey: Self.key)
  }
}
