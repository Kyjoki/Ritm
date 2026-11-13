import Foundation

/// Which periods of the hour grid (a day, three days or a week) are built, and which of them the
/// screen shows.
///
/// The grid keeps the visible period and its two neighbours alive as separate pages, so a swipe
/// only moves pages that already exist: nothing is created or torn down while the slide runs.
/// A page is a *slot*: a whole number that never changes its meaning, so the page keeps its
/// identity when the screen moves to the next one. After a move the neighbour it leaves behind is
/// still alive and the one ahead is built a moment later (`warmUp`), never in the frame the move
/// ends in. A jump to a period that is not a neighbour (today, a date from the mini-month, a
/// change of view) starts a new window without a slide.
public struct CalendarPagerWindow: Equatable, Sendable {
  public private(set) var mode: CalendarViewMode
  /// Changes with every new window, so pages of an earlier window are never reused.
  public private(set) var epoch: Int
  /// The slot shown on the screen when the move is over.
  public private(set) var slot: Int
  /// Whether both neighbours of `slot` are built.
  public private(set) var warm: Bool
  /// The page the last move came from: it stays alive, and is the neighbour behind.
  private var behind: Int?
  private let baseAnchor: String
  private let baseSlot: Int

  /// A window that shows `days` at `slot`. A new window keeps the number of the slot it replaces, so
  /// the strip does not have to move to show it.
  public init(mode: CalendarViewMode, days: [String], epoch: Int = 0, slot: Int = 0) {
    self.mode = mode
    self.epoch = epoch
    self.slot = slot
    baseSlot = slot
    baseAnchor = days.first ?? ""
    warm = false
    behind = nil
  }

  /// The days of the period at `slot`: the visible days of that anchor.
  public func days(slot: Int) -> [String] {
    mode.visibleDays(anchor: mode.stepped(anchor: baseAnchor, by: slot - baseSlot))
  }

  public var currentDays: [String] { days(slot: slot) }

  /// True when the window shows exactly these days in this view.
  public func matches(mode: CalendarViewMode, days: [String]) -> Bool {
    self.mode == mode && currentDays == days
  }

  /// The window to draw for `days`: this one when it already shows them, otherwise a new one at
  /// `slot` (the number of this window's slot when none is given).
  public func aligned(mode: CalendarViewMode, days: [String], slot newSlot: Int? = nil)
    -> CalendarPagerWindow
  {
    matches(mode: mode, days: days)
      ? self : CalendarPagerWindow(mode: mode, days: days, epoch: epoch + 1, slot: newSlot ?? slot)
  }

  /// The slots that are built, in order: the current one, the one the move came from, and, once
  /// the window is warm, both neighbours.
  public var slots: [Int] {
    var wanted: Set<Int> = [slot]
    if let behind { wanted.insert(behind) }
    if warm {
      wanted.insert(slot - 1)
      wanted.insert(slot + 1)
    }
    return wanted.sorted()
  }

  /// Moves one period forward (1) or back (-1) after the slide has finished.
  public mutating func commit(direction: Int) {
    guard direction != 0 else { return }
    behind = slot
    slot += direction > 0 ? 1 : -1
    warm = false
  }

  /// The move is over and the page is quiet: build the neighbours.
  public mutating func warmUp() {
    warm = true
    behind = nil
  }

  /// The neighbour a finger can drag towards must exist: true when a page for `direction` is
  /// missing and `warmUp` has to run before the drag shows anything.
  public func needsWarmUp(direction: Int) -> Bool {
    !slots.contains(slot + (direction > 0 ? 1 : -1))
  }

  /// The days worth computing ahead for the layouts while the phone is idle: two periods each way
  /// around the current one, nearest first.
  public func daysToPrepare() -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for offset in [0, 1, -1, 2, -2] {
      for day in days(slot: slot + offset) where seen.insert(day).inserted { result.append(day) }
    }
    return result
  }
}
