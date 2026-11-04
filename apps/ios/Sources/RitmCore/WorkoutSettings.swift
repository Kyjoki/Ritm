import Foundation

/// «Настройки тренировок»: which habit a finished workout ticks. One doc, synced.
public struct WorkoutSettings: Codable, Equatable, Sendable {
  /// The doc id on the server (there is only one).
  public static let docID = "workouts"

  public var linkedHabitID: String?
  /// The day (`yyyy-MM-dd`) a finished workout last ticked the habit: once per day.
  public var lastTickedDay: String?

  public init(linkedHabitID: String? = nil, lastTickedDay: String? = nil) {
    self.linkedHabitID = linkedHabitID
    self.lastTickedDay = lastTickedDay
  }

  private enum CodingKeys: String, CodingKey { case linkedHabitID, lastTickedDay }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      linkedHabitID: try? c.decodeIfPresent(String.self, forKey: .linkedHabitID),
      lastTickedDay: try? c.decodeIfPresent(String.self, forKey: .lastTickedDay))
  }

  /// Nothing to remember: the doc is then absent (deleted) on the server too.
  public var isDefault: Bool { linkedHabitID == nil && lastTickedDay == nil }
}

public enum WorkoutHabitLink {
  /// Whether finishing a workout today should tick the linked habit: the habit exists, can be
  /// marked today, is not complete yet, and this workout log has not ticked it today already.
  public static func shouldTick(habit: Habit?, settings: WorkoutSettings, today: String) -> Bool {
    guard let habit, habit.id == settings.linkedHabitID, settings.lastTickedDay != today,
      HabitSchedule.canMark(habit, on: today, today: today),
      HabitSchedule.progress(habit, on: today) < HabitSchedule.target(habit)
    else { return false }
    return true
  }
}
