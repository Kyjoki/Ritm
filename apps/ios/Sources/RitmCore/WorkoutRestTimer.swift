import Foundation

/// The rest timer between sets, as a small pure value so it can be reused later (for example for
/// a Live Activity). It never counts anything: while it runs it holds the ABSOLUTE `endDate`, so
/// the remaining time is always `endDate - now`, whatever happened to the app in between.
public struct RestTimer: Codable, Equatable, Sendable {
  public static let presets: [TimeInterval] = [60, 90, 120, 180]
  public static let defaultPreset: TimeInterval = 180
  /// What «+15 с» adds.
  public static let extensionStep: TimeInterval = 15

  public enum Phase: Equatable, Sendable { case idle, running, paused, finished }

  public private(set) var preset: TimeInterval
  /// Set while the timer runs (or has just run out).
  public private(set) var endDate: Date?
  /// Set while the timer is paused.
  public private(set) var pausedRemaining: TimeInterval?
  /// How long the current rest was meant to last (an exercise can rest longer than the preset,
  /// and «+15 с» adds to it): the full circle of the countdown ring. `nil` means the preset.
  public private(set) var length: TimeInterval?

  public init(preset: TimeInterval = RestTimer.defaultPreset) {
    self.preset = Self.presets.contains(preset) ? preset : Self.defaultPreset
  }

  private enum CodingKeys: String, CodingKey { case preset, endDate, pausedRemaining, length }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(preset: c.workoutValue(.preset, Self.defaultPreset))
    endDate = try? c.decodeIfPresent(Date.self, forKey: .endDate)
    if let paused = try? c.decodeIfPresent(TimeInterval.self, forKey: .pausedRemaining),
      paused.isFinite, paused > 0
    {
      pausedRemaining = paused
    }
    if endDate != nil { pausedRemaining = nil }
    if let saved = try? c.decodeIfPresent(TimeInterval.self, forKey: .length), saved.isFinite, saved > 0 {
      length = saved
    }
  }

  /// The full length the ring counts down from.
  public var totalLength: TimeInterval { length ?? preset }

  public func phase(now: Date) -> Phase {
    if let endDate { return now >= endDate ? .finished : .running }
    return pausedRemaining != nil ? .paused : .idle
  }

  /// Seconds left, never negative: zero once it has run out.
  public func remaining(now: Date) -> TimeInterval {
    switch phase(now: now) {
    case .running: return max(0, (endDate ?? now).timeIntervalSince(now))
    case .paused: return max(0, pausedRemaining ?? 0)
    case .idle: return preset
    case .finished: return 0
    }
  }

  /// Starts a full rest, resumes a paused one, and leaves a running one alone.
  public mutating func start(now: Date) {
    switch phase(now: now) {
    case .running: return
    case .paused:
      endDate = now.addingTimeInterval(pausedRemaining ?? preset)
      pausedRemaining = nil
    case .idle, .finished:
      endDate = now.addingTimeInterval(preset)
      pausedRemaining = nil
      length = nil
    }
  }

  public mutating func pause(now: Date) {
    guard phase(now: now) == .running, let endDate else { return }
    pausedRemaining = max(0, endDate.timeIntervalSince(now))
    self.endDate = nil
  }

  /// A fresh full rest, whatever the state was (what a ticked set does).
  public mutating func restart(now: Date) {
    endDate = now.addingTimeInterval(preset)
    pausedRemaining = nil
    length = nil
  }

  /// A fresh rest of `seconds` (the exercise's own rest); the preset stays as it is.
  public mutating func restart(now: Date, seconds: TimeInterval) {
    guard seconds.isFinite, seconds > 0 else { return restart(now: now) }
    endDate = now.addingTimeInterval(seconds)
    pausedRemaining = nil
    length = seconds
  }

  /// Back to the idle state with the chosen preset.
  public mutating func reset() {
    endDate = nil
    pausedRemaining = nil
    length = nil
  }

  /// «Пропустить»: ends the rest at once.
  public mutating func skip() { reset() }

  /// Adds time to a running or paused rest; an idle or finished one starts with just that.
  public mutating func extend(now: Date, by seconds: TimeInterval = RestTimer.extensionStep) {
    switch phase(now: now) {
    case .running:
      endDate = endDate?.addingTimeInterval(seconds)
      length = totalLength + seconds
    case .paused:
      pausedRemaining = (pausedRemaining ?? 0) + seconds
      length = totalLength + seconds
    case .idle, .finished:
      endDate = now.addingTimeInterval(seconds)
      pausedRemaining = nil
      length = seconds
    }
  }

  /// Chooses a preset. A running or paused rest restarts with it; otherwise only the preset changes.
  public mutating func setPreset(_ value: TimeInterval, now: Date) {
    guard Self.presets.contains(value) else { return }
    let phase = phase(now: now)
    preset = value
    switch phase {
    case .running:
      endDate = now.addingTimeInterval(value)
      length = nil
    case .paused:
      pausedRemaining = value
      length = nil
    case .idle, .finished: reset()
    }
  }
}

/// Clock text for the elapsed time and the rest timer.
public enum WorkoutClock {
  /// «05:07», then «1:05:07» once an hour has passed.
  public static func elapsed(from start: Date, now: Date) -> String {
    format(seconds: Int(max(0, now.timeIntervalSince(start)).rounded(.down)))
  }

  public static func format(seconds: Int) -> String {
    let total = max(0, seconds)
    let hours = total / 3600
    let minutes = (total / 60) % 60
    let rest = total % 60
    let mm = String(format: "%02d", minutes)
    let ss = String(format: "%02d", rest)
    return hours > 0 ? "\(hours):\(mm):\(ss)" : "\(mm):\(ss)"
  }

  /// The rest timer shows whole seconds counting down: 1.2 s left reads «00:02».
  public static func rest(remaining: TimeInterval) -> String {
    format(seconds: Int(max(0, remaining).rounded(.up)))
  }
}
