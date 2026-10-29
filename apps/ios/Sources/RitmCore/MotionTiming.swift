import Foundation

/// Pure rules of the count-up numbers (MOTION.md §3): where a count starts, how long it runs,
/// the ease-out cubic between two values and when it must not run at all.
public enum CountInterpolation {
  /// A first appearance starts from this share of the final value.
  public static let startShare = 0.35
  public static let firstDuration = 0.6
  public static let changeDuration = 0.45

  /// The value a count starts from: the previous value when there is one, else 35 % of the final.
  public static func start(final: Double, previous: Double?) -> Double {
    if let previous, previous.isFinite { return previous }
    return final.isFinite ? final * startShare : final
  }

  public static func duration(isFirst: Bool) -> Double {
    isFirst ? firstDuration : changeDuration
  }

  /// `1 - (1 - t)^3`, clamped to 0...1.
  public static func easeOutCubic(_ progress: Double) -> Double {
    let clamped = min(1, max(0, progress))
    let inverse = 1 - clamped
    return 1 - inverse * inverse * inverse
  }

  /// The displayed value after `progress` (0...1 of the duration) of a count from `from` to `to`.
  public static func value(from: Double, to: Double, progress: Double) -> Double {
    from + (to - from) * easeOutCubic(progress)
  }

  /// A count only runs between two different finite values; an unchanged value never replays.
  public static func shouldAnimate(from: Double, to: Double) -> Bool {
    from.isFinite && to.isFinite && from != to
  }
}

/// Stagger of the children of a page (MOTION.md §2): 45 ms per child, the first eight only.
public enum MotionStagger {
  public static let step = 0.045
  public static let cap = 8

  /// Delay in seconds before the child at `index` starts; later children share the last delay.
  public static func delay(index: Int) -> Double {
    Double(min(max(0, index), cap - 1)) * step
  }
}
