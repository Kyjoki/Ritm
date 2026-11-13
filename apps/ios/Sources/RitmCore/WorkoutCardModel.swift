import Foundation

/// What the table of one exercise of the running workout shows, worked out once when the exercise
/// changes instead of once per row on every render. Pure and `Equatable`: the screen compares two
/// models (or the items they come from) and skips the whole table when nothing it shows changed,
/// so swiping between exercises and typing in one set never rebuild the other exercises.
public struct WorkoutCardModel: Equatable, Sendable {
  /// One row of the table with everything its cells print already formatted.
  public struct Row: Equatable, Sendable, Identifiable {
    public let set: WorkoutSet
    public let index: Int
    /// The first set that is not done: the one the owner is working on.
    public let isActive: Bool
    /// «62,5 × 8» from the last workout, or «—» when that set did not exist then.
    public let previousText: String

    public var id: String { self.set.id }
  }

  public let rows: [Row]
  public let activeIndex: Int?
  public let doneCount: Int
  public let canRemoveSet: Bool
  public let canAddSet: Bool

  public static let noPrevious = "—"

  public static func make(item: WorkoutSessionItem, comma: Bool) -> WorkoutCardModel {
    let active = item.sets.firstIndex { !$0.done }
    var rows: [Row] = []
    rows.reserveCapacity(item.sets.count)
    for (index, set) in item.sets.enumerated() {
      let previous = item.previous?.set(at: index).map {
        "\(WorkoutFormat.weight($0.weight, comma: comma)) × \($0.reps)"
      }
      rows.append(
        Row(set: set, index: index, isActive: index == active, previousText: previous ?? noPrevious))
    }
    return WorkoutCardModel(
      rows: rows, activeIndex: active, doneCount: item.sets.reduce(0) { $0 + ($1.done ? 1 : 0) },
      canRemoveSet: item.sets.count > 1 && active != nil,
      canAddSet: item.sets.count < WorkoutSessionItem.maxSets)
  }

  /// The set the ± stepper changes while nothing was chosen: the leading set, or the last one
  /// when every set is done.
  public var leadingSetID: String? {
    if let activeIndex { return rows[activeIndex].set.id }
    return rows.last?.set.id
  }
}
