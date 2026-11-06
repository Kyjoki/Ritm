import Foundation

/// These are opaque context markers, never login/session credentials. Persisting the marker
/// permits a legitimate notification tap after cold launch; sign-out rotates it synchronously.
@MainActor public enum AccountSurfaceContext {
  private static let key = "ritm.account.surface-context.v1"
  public static func current(defaults: UserDefaults = .standard) -> String {
    if let value = defaults.string(forKey: key), UUID(uuidString: value) != nil { return value }
    return rotate(defaults: defaults)
  }
  public static func rotate(defaults: UserDefaults = .standard) -> String {
    let value = UUID().uuidString
    defaults.set(value, forKey: key)
    return value
  }
}

/// The app passes a cryptographic digest of its durable workout; no journal or weights are
/// duplicated here. An unchanged journal keeps its revision through a process restart.
@MainActor public enum WorkoutSurfaceRevision {
  public static func current(fingerprint: Data, defaults: UserDefaults = .standard) -> String {
    let key = "ritm.workout.surface-revision.v1"
    if defaults.data(forKey: key + ".digest") == fingerprint,
      let saved = defaults.string(forKey: key), UUID(uuidString: saved) != nil { return saved }
    let next = UUID().uuidString
    defaults.set(fingerprint, forKey: key + ".digest")
    defaults.set(next, forKey: key)
    return next
  }
}
