import Foundation

/// The program editor's working copy: nothing reaches the library until «Сохранить», and
/// «Отмена» simply drops the draft.
public struct WorkoutProgramDraft: Equatable, Sendable {
  public enum Field: Sendable { case sets, reps, rest }

  public var name: String
  public var colorIndex: Int
  public var items: [WorkoutProgramItem]

  public init(name: String = "", colorIndex: Int = 0, items: [WorkoutProgramItem] = []) {
    self.name = name
    self.colorIndex = min(max(colorIndex, 0), WorkoutProgram.colorCount - 1)
    self.items = items
  }

  public init(program: WorkoutProgram) {
    self.init(name: program.name, colorIndex: program.colorIndex, items: program.items)
  }

  public var trimmedName: String {
    String(
      name.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(WorkoutProgram.nameLimit))
  }

  /// A program needs a name and at least one exercise.
  public var canSave: Bool { !trimmedName.isEmpty && !items.isEmpty }

  /// A new exercise gets 3 sets of 10 and the default 180 s rest. `false` for a duplicate.
  @discardableResult
  public mutating func add(exerciseID: String, id: String = WorkoutID.make()) -> Bool {
    guard !items.contains(where: { $0.exerciseID == exerciseID }) else { return false }
    items.append(WorkoutProgramItem(id: id, exerciseID: exerciseID, sets: 3))
    return true
  }

  public mutating func remove(_ itemID: String) { items.removeAll { $0.id == itemID } }

  public mutating func move(from: Int, to: Int) { items = WorkoutOrder.moving(items, from: from, to: to) }

  public func value(_ itemID: String, _ field: Field) -> Int? {
    guard let item = items.first(where: { $0.id == itemID }) else { return nil }
    switch field {
    case .sets: return item.sets
    case .reps: return item.reps
    case .rest: return item.restSeconds
    }
  }

  /// Whether one more step up (`+1`) or down (`-1`) stays inside the field's range.
  public func canStep(_ itemID: String, _ field: Field, direction: Int) -> Bool {
    guard let current = value(itemID, field) else { return false }
    let range = Self.range(field)
    let next = current + direction * Self.step(field)
    return range.contains(next)
  }

  /// +1 / −1 step of sets (1), reps (1) or rest (15 s), stopping at the range ends.
  public mutating func step(_ itemID: String, _ field: Field, direction: Int) {
    guard canStep(itemID, field, direction: direction),
      let index = items.firstIndex(where: { $0.id == itemID })
    else { return }
    let delta = direction * Self.step(field)
    switch field {
    case .sets: items[index].sets += delta
    case .reps: items[index].reps += delta
    case .rest: items[index].restSeconds += delta
    }
  }

  private static func range(_ field: Field) -> ClosedRange<Int> {
    switch field {
    case .sets: WorkoutProgramItem.setRange
    case .reps: WorkoutProgramItem.repsRange
    case .rest: WorkoutProgramItem.restRange
    }
  }

  private static func step(_ field: Field) -> Int { field == .rest ? WorkoutProgramItem.restStep : 1 }
}

extension WorkoutLibrary {
  /// Writes the draft as program `id`: replaces that program, or adds it at the end when it does
  /// not exist yet. Nothing is written for a draft that cannot be saved.
  @discardableResult
  public mutating func save(_ draft: WorkoutProgramDraft, as id: String) -> Bool {
    guard draft.canSave else { return false }
    let program = WorkoutProgram(
      id: id, name: draft.trimmedName, items: draft.items, colorIndex: draft.colorIndex)
    if let index = programs.firstIndex(where: { $0.id == id }) {
      programs[index] = program
    } else {
      programs.append(program)
    }
    return true
  }
}

/// The ±2,5 kg / ±1 rep stepper of an active workout set.
public enum WorkoutStepper {
  public static let weightStep = 2.5
  public static let maxWeight = 9999.0

  /// The weight text after a step: never below 0, comma or dot as the owner types.
  public static func weight(_ text: String, delta: Double, comma: Bool) -> String {
    let current = WorkoutNumber.weight(text) ?? 0
    let next = min(maxWeight, max(0, ((current + delta) * 100).rounded() / 100))
    return WorkoutFormat.weight(next, comma: comma)
  }

  /// The reps text after a step, 1 to 999.
  public static func reps(_ text: String, delta: Int) -> String {
    String(min(999, max(1, (WorkoutNumber.reps(text) ?? 0) + delta)))
  }
}
