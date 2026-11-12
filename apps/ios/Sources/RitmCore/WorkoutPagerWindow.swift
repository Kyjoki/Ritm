import Foundation

/// Which exercise cards of the running workout are alive, and how the screen moves between them.
///
/// The screen keeps the current card and its two neighbours built, so a swipe only slides cards
/// that already exist instead of building the next table while the animation runs. The neighbours
/// are built a moment after the move has settled (`settle()`), never in the frame it starts in.
/// A move to a card that is not next to the current one, or any move with Reduce Motion, does not
/// slide: it cross-fades (`fade`).
public struct WorkoutPagerWindow: Equatable, Sendable {
  public private(set) var current: Int
  /// The card the move came from; kept alive until the move has settled so it can slide away.
  public private(set) var previous: Int?
  /// Whether the neighbours of the current card are built.
  public private(set) var warm: Bool
  /// The last move cross-fades instead of sliding.
  public private(set) var fade: Bool

  /// Only the current card at first: the first frame of the screen builds one table, not three.
  public init(current: Int = 0) {
    self.current = max(0, current)
    previous = nil
    warm = false
    fade = false
  }

  /// A change that is not a swipe (the first appearance, the exercises reordered): no slide.
  public mutating func reset(to index: Int) {
    current = max(0, index)
    previous = nil
    warm = false
    fade = false
  }

  /// Moves to `index`. `fade` says the move cross-fades because it is far or motion is reduced.
  public mutating func move(to index: Int, reduceMotion: Bool) {
    guard index >= 0, index != current else { return }
    fade = reduceMotion || abs(index - current) > 1
    previous = current
    current = index
    warm = false
  }

  /// The move is over: the card it came from is no longer needed and the neighbours of the
  /// current card may be built.
  public mutating func settle() {
    previous = nil
    warm = true
  }

  /// Positions of the cards that are alive, in order, for a workout of `count` exercises.
  public func indices(count: Int) -> [Int] {
    guard count > 0 else { return [] }
    let focus = min(current, count - 1)
    var wanted: Set<Int> = [focus]
    if let previous, !fade { wanted.insert(previous) }
    if warm {
      wanted.insert(focus - 1)
      wanted.insert(focus + 1)
    }
    return wanted.filter { (0..<count).contains($0) }.sorted()
  }
}
