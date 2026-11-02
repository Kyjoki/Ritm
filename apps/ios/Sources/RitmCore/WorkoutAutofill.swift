import Foundation

// Weight and reps as the owner types them, and the shared-weight auto-fill of an exercise.

public enum WorkoutNumber {
  /// A weight as typed, cleaned up: «22,» becomes «22», «.5» becomes «0.5», «2,50» stays. The
  /// separator the owner used is kept. `nil` for anything that is not a (partly typed) weight,
  /// such as «», «.», «2.5.» or «12345»: such input must never be passed on to other fields.
  public static func normalizedWeight(_ raw: String) -> String? {
    let text = raw.trimmingCharacters(in: .whitespaces)
    var integer = ""
    var separator: Character?
    var fraction = ""
    for character in text {
      if character.isASCII, character.isNumber {
        if separator == nil { integer.append(character) } else { fraction.append(character) }
      } else if (character == "." || character == ","), separator == nil {
        separator = character
      } else {
        return nil
      }
    }
    guard integer.count <= 4, fraction.count <= 2 else { return nil }
    if integer.isEmpty {
      guard separator != nil, !fraction.isEmpty else { return nil }
      integer = "0"
    }
    guard let separator, !fraction.isEmpty else { return integer }
    return "\(integer)\(separator)\(fraction)"
  }

  /// Kilograms, fractions allowed, a dot or a comma. A bodyweight exercise may be 0.
  public static func weight(_ raw: String) -> Double? {
    guard let normalized = normalizedWeight(raw) else { return nil }
    return Double(normalized.replacingOccurrences(of: ",", with: "."))
  }

  public static func reps(_ raw: String) -> Int? {
    let text = raw.trimmingCharacters(in: .whitespaces)
    guard (1...3).contains(text.count), text.allSatisfy({ $0.isASCII && $0.isNumber }),
      let value = Int(text), value > 0
    else { return nil }
    return value
  }

  public static func isBlank(_ raw: String) -> Bool {
    raw.trimmingCharacters(in: .whitespaces).isEmpty
  }
}

/// The auto-fill of the weight inside one exercise. Pure functions, no view code.
///
/// The leading set is the first set that is not done yet (set 1 until it is ticked). A weight
/// typed there is copied at once into every other unfinished set whose weight the owner did not
/// set by hand; those sets may hold values pre-filled from the last workout, which the shared
/// weight replaces. A weight typed into any other set stays that set's own; clearing the field
/// lets it follow the shared weight again from the next typing. Done sets are never touched, reps
/// are never copied and nothing is ticked automatically.
public enum WorkoutAutofill {
  public struct Outcome: Equatable, Sendable {
    public var sets: [WorkoutSet]
    public var sharedWeight: String
  }

  public static func leaderIndex(_ sets: [WorkoutSet]) -> Int? {
    sets.firstIndex { !$0.done }
  }

  /// The owner typed `text` into the weight field of set `setID`. The text is stored exactly as
  /// typed (a half-typed «2,» is kept as is); only a valid weight is passed on.
  public static func typeWeight(
    _ text: String, setID: String, sets: [WorkoutSet], sharedWeight: String
  ) -> Outcome {
    guard let index = sets.firstIndex(where: { $0.id == setID }), !sets[index].done else {
      return Outcome(sets: sets, sharedWeight: sharedWeight)
    }
    var next = sets
    next[index].weight = text
    guard index == leaderIndex(sets) else {
      next[index].edited = !WorkoutNumber.isBlank(text)
      return Outcome(sets: next, sharedWeight: sharedWeight)
    }
    next[index].edited = false
    guard let shared = WorkoutNumber.normalizedWeight(text) else {
      return Outcome(sets: next, sharedWeight: sharedWeight)
    }
    for other in next.indices where other != index && !next[other].done && !next[other].edited {
      next[other].weight = shared
    }
    return Outcome(sets: next, sharedWeight: shared)
  }

  /// A new set takes the last shared weight (or, before any was typed, the weight of the last
  /// set); its reps stay empty.
  public static func newSet(id: String, sets: [WorkoutSet], sharedWeight: String) -> WorkoutSet {
    let weight = WorkoutNumber.isBlank(sharedWeight) ? (sets.last?.weight ?? "") : sharedWeight
    return WorkoutSet(id: id, weight: weight, reps: "", done: false, edited: false)
  }
}

// MARK: - Editing an exercise of the active workout

extension WorkoutSessionItem {
  public enum TickResult: Equatable, Sendable {
    case done, undone, needsWeight, needsReps, missing
  }

  public mutating func typeWeight(_ text: String, setID: String) {
    let outcome = WorkoutAutofill.typeWeight(text, setID: setID, sets: sets, sharedWeight: sharedWeight)
    sets = outcome.sets
    sharedWeight = outcome.sharedWeight
  }

  public mutating func typeReps(_ text: String, setID: String) {
    guard let index = sets.firstIndex(where: { $0.id == setID }), !sets[index].done else { return }
    sets[index].reps = text
  }

  /// Ticks or unticks a set. A tick needs a valid weight and reps; the values are cleaned up
  /// then. An unticked set can be corrected and ticked again.
  public mutating func toggle(setID: String) -> TickResult {
    guard let index = sets.firstIndex(where: { $0.id == setID }) else { return .missing }
    if sets[index].done {
      sets[index].done = false
      return .undone
    }
    guard let normalized = WorkoutNumber.normalizedWeight(sets[index].weight),
      WorkoutNumber.weight(sets[index].weight) != nil
    else { return .needsWeight }
    guard let reps = WorkoutNumber.reps(sets[index].reps) else { return .needsReps }
    sets[index].weight = normalized
    sets[index].reps = String(reps)
    sets[index].done = true
    return .done
  }

  @discardableResult
  public mutating func addSet(id: String = WorkoutID.make()) -> Bool {
    guard sets.count < Self.maxSets else { return false }
    sets.append(WorkoutAutofill.newSet(id: id, sets: sets, sharedWeight: sharedWeight))
    return true
  }

  /// A completed set is never deleted by accident: untick it first. The last set stays.
  @discardableResult
  public mutating func removeSet(setID: String) -> Bool {
    guard sets.count > 1, let index = sets.firstIndex(where: { $0.id == setID }), !sets[index].done
    else { return false }
    sets.remove(at: index)
    return true
  }
}

// MARK: - Comparison with the last time

/// «+2,5 кг · −1 повт.» versus the same set last time.
public struct WorkoutDelta: Equatable, Sendable {
  public let weight: Double
  public let reps: Int

  public var isZero: Bool { weight == 0 && reps == 0 }

  /// `nil` when the set is not done, has no counterpart last time or holds an invalid value.
  public static func make(set: WorkoutSet, previous: WorkoutResultSet?) -> WorkoutDelta? {
    guard set.done, let previous, let weight = WorkoutNumber.weight(set.weight),
      let reps = WorkoutNumber.reps(set.reps)
    else { return nil }
    return WorkoutDelta(weight: ((weight - previous.weight) * 100).rounded() / 100, reps: reps - previous.reps)
  }
}
