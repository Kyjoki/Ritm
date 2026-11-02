import Foundation

// Pure operations on programs and on the active workout. The view model only calls these.

public enum WorkoutOrder {
  /// The array with the element at `from` moved so that it ends up at index `to`. Out-of-range
  /// indexes leave it as it was.
  public static func moving<T>(_ items: [T], from: Int, to: Int) -> [T] {
    guard items.indices.contains(from), items.indices.contains(to), from != to else { return items }
    var result = items
    let element = result.remove(at: from)
    result.insert(element, at: to)
    return result
  }
}

// MARK: - Exercise catalog

public enum WorkoutCatalog {
  private static let builtinNames: [(id: String, ru: String, en: String)] = [
    ("bench", "Жим лёжа", "Bench press"),
    ("incline", "Жим гантелей на наклонной", "Incline dumbbell press"),
    ("fly", "Разводка гантелей", "Dumbbell fly"),
    ("french", "Французский жим", "Skull crusher"),
    ("deadlift", "Становая тяга", "Deadlift"),
    ("pullup", "Подтягивания", "Pull-up"),
    ("row", "Тяга штанги в наклоне", "Barbell row"),
    ("pulldown", "Тяга верхнего блока", "Lat pulldown"),
    ("curl", "Подъём штанги на бицепс", "Barbell curl"),
    ("squat", "Присед со штангой", "Barbell squat"),
    ("legpress", "Жим ногами", "Leg press"),
    ("rdl", "Румынская тяга", "Romanian deadlift"),
    ("ohp", "Жим стоя", "Overhead press"),
    ("lunge", "Выпады с гантелями", "Dumbbell lunge"),
    ("dips", "Отжимания на брусьях", "Dips"),
    ("crunch", "Скручивания", "Crunch"),
    ("lateral", "Махи гантелями в стороны", "Lateral raise"),
    ("legraise", "Подъём ног в висе", "Hanging leg raise"),
    ("twist", "Русские скручивания", "Russian twist"),
  ]

  /// Built-in ids are stable and never depend on the language.
  public static func builtinID(_ key: String) -> String { "builtin." + key }

  public static func builtin(language: Language) -> [WorkoutExercise] {
    builtinNames.map {
      WorkoutExercise(id: builtinID($0.id), name: language == .ru ? $0.ru : $0.en)
    }
  }

  public static func all(custom: [WorkoutExercise], language: Language) -> [WorkoutExercise] {
    builtin(language: language) + custom
  }

  public static func name(of id: String, custom: [WorkoutExercise], language: Language) -> String? {
    all(custom: custom, language: language).first { $0.id == id }?.name
  }
}

// MARK: - Programs

extension WorkoutLibrary {
  public func program(_ id: String) -> WorkoutProgram? { programs.first { $0.id == id } }

  public func exerciseName(_ id: String, language: Language) -> String {
    WorkoutCatalog.name(of: id, custom: customExercises, language: language)
      ?? (language == .ru ? "Упражнение" : "Exercise")
  }

  @discardableResult
  public mutating func addProgram(name: String, id: String = WorkoutID.make()) -> String {
    programs.append(WorkoutProgram(id: id, name: Self.clean(name)))
    return id
  }

  public mutating func renameProgram(_ id: String, to name: String) {
    update(id) { $0.name = String(name.prefix(WorkoutProgram.nameLimit)) }
  }

  /// A copy right after the original, with fresh ids so the two never share state.
  @discardableResult
  public mutating func duplicateProgram(
    _ id: String, suffix: String, makeID: () -> String = WorkoutID.make
  ) -> String? {
    guard let index = programs.firstIndex(where: { $0.id == id }) else { return nil }
    let original = programs[index]
    let copy = WorkoutProgram(
      id: makeID(), name: Self.clean(original.name + suffix),
      items: original.items.map {
        WorkoutProgramItem(id: makeID(), exerciseID: $0.exerciseID, sets: $0.sets)
      })
    programs.insert(copy, at: index + 1)
    return copy.id
  }

  public mutating func deleteProgram(_ id: String) {
    programs.removeAll { $0.id == id }
  }

  public mutating func moveProgram(from: Int, to: Int) {
    programs = WorkoutOrder.moving(programs, from: from, to: to)
  }

  @discardableResult
  public mutating func addItem(
    to programID: String, exerciseID: String, sets: Int = 3, id: String = WorkoutID.make()
  ) -> Bool {
    guard let found = program(programID), !found.items.contains(where: { $0.exerciseID == exerciseID })
    else { return false }
    update(programID) { $0.items.append(WorkoutProgramItem(id: id, exerciseID: exerciseID, sets: sets)) }
    return true
  }

  public mutating func removeItem(_ itemID: String, from programID: String) {
    update(programID) { $0.items.removeAll { $0.id == itemID } }
  }

  /// Replaces the exercise but keeps its place and its planned set count.
  @discardableResult
  public mutating func replaceItem(_ itemID: String, in programID: String, with exerciseID: String) -> Bool {
    guard let found = program(programID), !found.items.contains(where: { $0.exerciseID == exerciseID })
    else { return false }
    update(programID) { program in
      program.items = program.items.map {
        $0.id == itemID ? WorkoutProgramItem(id: $0.id, exerciseID: exerciseID, sets: $0.sets) : $0
      }
    }
    return true
  }

  public mutating func setPlannedSets(_ count: Int, item itemID: String, in programID: String) {
    update(programID) { program in
      program.items = program.items.map {
        $0.id == itemID ? WorkoutProgramItem(id: $0.id, exerciseID: $0.exerciseID, sets: count) : $0
      }
    }
  }

  public mutating func moveItem(in programID: String, from: Int, to: Int) {
    update(programID) { $0.items = WorkoutOrder.moving($0.items, from: from, to: to) }
  }

  /// The owner's own exercise. A name that already exists (built-in in either language, or
  /// custom, any letter case) returns that exercise instead of a duplicate. Names are 2–40
  /// characters.
  public mutating func createExercise(
    named raw: String, id: String = WorkoutID.make()
  ) -> WorkoutExercise? {
    let name = Self.clean(raw, limit: 40)
    guard name.count >= 2 else { return nil }
    let key = name.lowercased()
    for language in Language.allCases {
      if let found = WorkoutCatalog.all(custom: customExercises, language: language)
        .first(where: { $0.name.lowercased() == key })
      {
        return found
      }
    }
    let exercise = WorkoutExercise(id: "custom." + id, name: name)
    customExercises.append(exercise)
    return exercise
  }

  private mutating func update(_ id: String, _ change: (inout WorkoutProgram) -> Void) {
    guard let index = programs.firstIndex(where: { $0.id == id }) else { return }
    change(&programs[index])
  }

  static func clean(_ raw: String, limit: Int = WorkoutProgram.nameLimit) -> String {
    let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return String(collapsed.prefix(limit))
  }
}

// MARK: - Starting, replacing and finishing a workout

extension WorkoutSessionItem {
  /// An exercise of a workout: «last time» comes from completed workouts of THIS exercise id
  /// only, and the sets are pre-filled from it. Pre-filled values never count as done.
  public static func make(
    exerciseID: String, name: String, setCount: Int, history: WorkoutHistory,
    makeID: () -> String = WorkoutID.make
  ) -> WorkoutSessionItem {
    let previous = history.lastResult(exerciseID: exerciseID)
    let sets = (0..<max(1, setCount)).map { index -> WorkoutSet in
      let result = previous.flatMap { $0.set(at: index) ?? $0.sets.last }
      return WorkoutSet(
        id: makeID(), weight: result.map { WorkoutFormat.weight($0.weight) } ?? "",
        reps: result.map { String($0.reps) } ?? "")
    }
    return WorkoutSessionItem(
      id: makeID(), exerciseID: exerciseID, name: name, previous: previous, sets: sets)
  }
}

extension WorkoutSession {
  /// «Начать тренировку»: a separate snapshot of the program, named as it is now. `nil` for a
  /// program with no exercises.
  public static func start(
    program: WorkoutProgram, library: WorkoutLibrary, history: WorkoutHistory, language: Language,
    now: Date, makeID: () -> String = WorkoutID.make
  ) -> WorkoutSession? {
    guard !program.items.isEmpty else { return nil }
    let items = program.items.map {
      WorkoutSessionItem.make(
        exerciseID: $0.exerciseID, name: library.exerciseName($0.exerciseID, language: language),
        setCount: $0.sets, history: history, makeID: makeID)
    }
    return WorkoutSession(
      id: makeID(), programID: program.id, programName: program.name, startedAt: now, items: items)
  }

  public func item(_ id: String) -> WorkoutSessionItem? { items.first { $0.id == id } }

  public mutating func update(_ itemID: String, _ change: (inout WorkoutSessionItem) -> Void) {
    guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
    change(&items[index])
  }

  /// Replaces an exercise DURING the workout. The new one shows its own last results. Sets that
  /// are already done stay logged under the old exercise (which keeps only them); the unfinished
  /// ones move to the new exercise. With nothing done yet the old exercise is simply swapped.
  public mutating func replaceExercise(
    _ itemID: String, with exerciseID: String, name: String, history: WorkoutHistory,
    makeID: () -> String = WorkoutID.make
  ) {
    guard let index = items.firstIndex(where: { $0.id == itemID }),
      !items.contains(where: { $0.exerciseID == exerciseID })
    else { return }
    let old = items[index]
    let open = old.sets.filter { !$0.done }.count
    let replacement = WorkoutSessionItem.make(
      exerciseID: exerciseID, name: name, setCount: max(1, open), history: history, makeID: makeID)
    if old.sets.contains(where: \.done) {
      items[index].sets = old.sets.filter(\.done)
      items.insert(replacement, at: index + 1)
    } else {
      items[index] = replacement
    }
  }

  /// The history entry for what was ticked, or `nil` when nothing was. Only done sets count.
  public func finished(at end: Date) -> WorkoutRecord? {
    let exercises = items.compactMap { item -> WorkoutRecordExercise? in
      let sets = item.sets.compactMap { set -> WorkoutResultSet? in
        guard set.done, let weight = WorkoutNumber.weight(set.weight),
          let reps = WorkoutNumber.reps(set.reps)
        else { return nil }
        return WorkoutResultSet(weight: weight, reps: reps)
      }
      return sets.isEmpty
        ? nil : WorkoutRecordExercise(exerciseID: item.exerciseID, name: item.name, sets: sets)
    }
    guard !exercises.isEmpty else { return nil }
    return WorkoutRecord(
      id: id, programID: programID, programName: programName, startedAt: startedAt, endedAt: end,
      exercises: exercises)
  }
}

// MARK: - Formatting

public enum WorkoutFormat {
  /// «62,5» or «62.5»; whole numbers have no fraction, two decimals at most.
  public static func weight(_ value: Double, comma: Bool = false) -> String {
    let rounded = (value * 100).rounded() / 100
    var text = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    if text.contains("."), text.hasSuffix("0") { text.removeLast() }
    return comma ? text.replacingOccurrences(of: ".", with: ",") : text
  }

  /// «+2,5 кг · −1 повт.», or the `same` text when nothing changed.
  public static func delta(
    _ delta: WorkoutDelta, comma: Bool, kg: String, reps: String, same: String
  ) -> String {
    if delta.isZero { return same }
    func signed(_ value: Double) -> String {
      (value > 0 ? "+" : "−") + weight(abs(value), comma: comma)
    }
    var parts: [String] = []
    if delta.weight != 0 { parts.append("\(signed(delta.weight))\u{00A0}\(kg)") }
    if delta.reps != 0 { parts.append("\(signed(Double(delta.reps)))\u{00A0}\(reps)") }
    return parts.joined(separator: " · ")
  }
}
