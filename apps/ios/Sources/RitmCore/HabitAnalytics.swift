import Foundation

/// How well one habit did over the days of a period.
public struct HabitRate: Sendable, Equatable {
  public let habitID: String
  public let title: String
  public let planned: Int
  public let completed: Int

  public init(habitID: String, title: String, planned: Int, completed: Int) {
    self.habitID = habitID
    self.title = title
    self.planned = planned
    self.completed = completed
  }

  public var percent: Int {
    planned > 0 ? Int((Double(completed) / Double(planned) * 100).rounded()) : 0
  }
}

/// What a habit looks like on one day of its week strip or calendar.
public enum HabitDayState: Sendable, Equatable { case future, off, done, part, miss }

/// A milestone of a habit's streak and the day the streak reached it for the last time.
public struct AchievementEvent: Sendable, Equatable {
  public let level: Int
  public let day: String

  public init(level: Int, day: String) {
    self.level = level
    self.day = day
  }
}

/// Everything about one habit that needs a walk through its whole history, computed in one pass.
public struct HabitStats: Sendable, Equatable {
  public let streak: Int
  public let best: Int
  /// The last time each level was reached, newest first.
  public let events: [AchievementEvent]

  public init(streak: Int, best: Int, events: [AchievementEvent]) {
    self.streak = streak
    self.best = best
    self.events = events
  }
}

/// «Награды»: one earned achievement of one habit.
public struct HabitAward: Sendable, Equatable, Identifiable {
  public let habitID: String
  public let title: String
  public let level: Int
  public let day: String
  public var id: String { "\(habitID)#\(level)" }

  public init(habitID: String, title: String, level: Int, day: String) {
    self.habitID = habitID
    self.title = title
    self.level = level
    self.day = day
  }
}

/// The nearest streak goal across the habits.
public struct HabitGoal: Sendable, Equatable {
  public let habitID: String
  public let title: String
  public let level: Int
  public let remaining: Int

  public init(habitID: String, title: String, level: Int, remaining: Int) {
    self.habitID = habitID
    self.title = title
    self.level = level
    self.remaining = remaining
  }
}

/// A habit's marks over a period: «N из M», the average and the share.
public struct HabitPeriodStats: Sendable, Equatable {
  public let planned: Int
  public let completed: Int
  public let total: Int
  public var percent: Int {
    planned > 0 ? Int((Double(completed) / Double(planned) * 100).rounded()) : 0
  }
  public var average: Int { planned > 0 ? Int((Double(total) / Double(planned)).rounded()) : 0 }
}

/// The numbers behind the redesigned habits page: the analytics card, the week strips, the
/// per-habit sheet and the awards. Everything here is pure; weeks start on Sunday.
public enum HabitAnalytics {
  /// The streak lengths that become achievements.
  public static let achievementLevels = [3, 7, 14, 30, 60, 100]
  /// Awards on the page start here; the shorter ones stay in the habit's own history.
  public static let awardMinimumLevel = 7
  public static let accentCount = 6
  /// How many days back the «good day» streak looks.
  public static let goodDayWindow = 130

  // MARK: Accent colour

  /// A stable palette slot for a habit: FNV-1a of its id, so it survives launches (`Hasher` is
  /// seeded per process) and never changes when the habit is renamed or reordered.
  public static func accentIndex(for id: String) -> Int {
    var hash: UInt32 = 2_166_136_261
    for byte in id.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
    return Int(hash % UInt32(accentCount))
  }

  // MARK: Period

  /// The day the list shows when a period is opened: today, else the last day already lived.
  public static func defaultDay(in dates: [String], today: String) -> String? {
    if dates.contains(today) { return today }
    return dates.last { $0 <= today } ?? dates.first
  }

  /// The share of scheduled marks done over a period; nil when nothing was scheduled.
  public static func periodPercent(_ habits: [Habit], dates: [String], today: String) -> Int? {
    HabitSchedule.periodSummary(habits, dates: dates, today: today).progress
  }

  public static func rates(_ habits: [Habit], dates: [String], today: String) -> [HabitRate] {
    habits.compactMap { habit in
      var planned = 0
      var completed = 0
      for day in dates where day <= today && HabitSchedule.isScheduled(habit, on: day) {
        planned += 1
        if HabitSchedule.isComplete(habit, on: day) { completed += 1 }
      }
      guard planned > 0 else { return nil }
      return HabitRate(habitID: habit.id, title: habit.title, planned: planned, completed: completed)
    }
  }

  /// Orders two rates by their share: positive when `a` did better than `b`.
  private static func shareOrder(_ a: HabitRate, _ b: HabitRate) -> Int {
    let left = a.completed * b.planned
    let right = b.completed * a.planned
    return left == right ? 0 : (left > right ? 1 : -1)
  }

  /// «Лучшая» and «Слабая привычка»: the highest and the lowest share, the habit with more
  /// scheduled marks winning a tie. The weak one is nil when it would be the best one again (a
  /// single habit, or every habit at the same share). Ties keep the earlier habit.
  public static func bestAndWorst(_ rates: [HabitRate]) -> (best: HabitRate?, worst: HabitRate?) {
    guard var best = rates.first, var worst = rates.first else { return (nil, nil) }
    for rate in rates.dropFirst() {
      let againstBest = shareOrder(rate, best)
      if againstBest > 0 || (againstBest == 0 && rate.planned > best.planned) { best = rate }
      let againstWorst = shareOrder(rate, worst)
      if againstWorst < 0 || (againstWorst == 0 && rate.planned > worst.planned) { worst = rate }
    }
    return shareOrder(best, worst) == 0 ? (best, nil) : (best, worst)
  }

  /// «+4% к прошлой неделе»: the period's share minus the share of the period before it. nil
  /// when either of them had nothing scheduled.
  public static func trend(_ habits: [Habit], today: String, month: Bool, offset: Int) -> Int? {
    let current = HabitsPlan.periodDates(today: today, month: month, offset: offset)
    let previous = HabitsPlan.periodDates(today: today, month: month, offset: offset - 1)
    guard let now = periodPercent(habits, dates: current, today: today),
      let before = periodPercent(habits, dates: previous, today: today)
    else { return nil }
    return now - before
  }

  /// A heat level 0...4 for a day of the month grid: 0 when nothing was done, then quarters.
  public static func intensity(_ summary: HabitDaySummary) -> Int {
    guard summary.completed > 0, summary.planned > 0 else { return 0 }
    let share = Double(summary.completed) / Double(summary.planned)
    switch share {
    case ...0.25: return 1
    case ...0.5: return 2
    case ...0.75: return 3
    default: return 4
    }
  }

  // MARK: «Good days»

  /// A day counts toward the overall streak when at least 60 % of its scheduled habits were
  /// done; nil when nothing was scheduled.
  public static func isGoodDay(_ habits: [Habit], on day: String) -> Bool? {
    let summary = HabitSchedule.daySummary(habits, on: day)
    guard summary.planned > 0 else { return nil }
    return summary.completed * 5 >= summary.planned * 3
  }

  /// The current and the best run of good days ending at `end`. Days without anything
  /// scheduled are skipped; today never breaks a run while it is still open.
  public static func goodDayStreaks(_ habits: [Habit], end: String, today: String)
    -> (current: Int, best: Int)
  {
    var days: [Bool?] = []
    days.reserveCapacity(goodDayWindow)
    var day = end
    for _ in 0..<goodDayWindow {
      days.append(isGoodDay(habits, on: day))
      guard let previous = HabitSchedule.addDays(to: day, days: -1) else { break }
      day = previous
    }
    // `days[0]` is `end`, older days follow.
    var current = 0
    var openDay = end == today
    for state in days {
      guard let good = state else {
        openDay = false
        continue
      }
      if good {
        current += 1
      } else if openDay {
        // Today may still be done.
      } else {
        break
      }
      openDay = false
    }
    var run = 0
    var best = 0
    for (index, state) in days.enumerated().reversed() {
      guard let good = state else { continue }
      if good {
        run += 1
        best = max(best, run)
      } else if !(index == 0 && end == today) {
        run = 0
      }
    }
    return (current, max(best, current))
  }

  // MARK: One habit

  /// A habit's day as the week strip and the calendar draw it.
  public static func dayState(_ habit: Habit, on day: String, today: String) -> HabitDayState {
    switch HabitsPlan.dayStatus(habit, on: day, today: today) {
    case .future: return .future
    case .before, .rest: return .off
    case .done: return .done
    case .pending: return HabitSchedule.progress(habit, on: day) > 0 ? .part : .miss
    }
  }

  /// 0...1: how much of the day's goal is done.
  public static func fraction(_ habit: Habit, on day: String) -> Double {
    let target = max(1, HabitSchedule.target(habit))
    return min(1, Double(HabitSchedule.progress(habit, on: day)) / Double(target))
  }

  /// «2 из 3 на неделе»: scheduled days of the week up to today, and how many were done.
  public static func weekCount(_ habit: Habit, containing day: String, today: String)
    -> (completed: Int, planned: Int)
  {
    let stats = periodStats(habit, dates: HabitSchedule.week(containing: day), today: today)
    return (stats.completed, stats.planned)
  }

  public static func periodStats(_ habit: Habit, dates: [String], today: String) -> HabitPeriodStats {
    var planned = 0
    var completed = 0
    var total = 0
    for day in dates where day <= today && HabitSchedule.isScheduled(habit, on: day) {
      planned += 1
      total += HabitSchedule.progress(habit, on: day)
      if HabitSchedule.isComplete(habit, on: day) { completed += 1 }
    }
    return HabitPeriodStats(planned: planned, completed: completed, total: total)
  }

  /// Streak, record and the days of every achievement in one walk through the history. The
  /// walk follows `HabitSchedule.bestStreak`: an archived stretch resets the run.
  public static func stats(_ habit: Habit, today: String) -> HabitStats {
    let streak = HabitSchedule.streak(habit, today: today)
    guard HabitSchedule.isValidDate(today), HabitSchedule.isValidDate(habit.startDate) else {
      return HabitStats(streak: streak, best: 0, events: [])
    }
    var best = 0
    var run = 0
    var reached: [Int: String] = [:]
    var day = habit.startDate
    while day <= today {
      if HabitSchedule.period(habit, on: day)?.archived ?? true {
        run = 0
      } else if HabitSchedule.isScheduled(habit, on: day) {
        if HabitSchedule.isComplete(habit, on: day) {
          run += 1
          best = max(best, run)
          if achievementLevels.contains(run) { reached[run] = day }
        } else {
          run = 0
        }
      }
      guard let next = HabitSchedule.addDays(to: day, days: 1), next > day else { break }
      day = next
    }
    let events = reached.map { AchievementEvent(level: $0.key, day: $0.value) }
      .sorted { $0.day != $1.day ? $0.day > $1.day : $0.level > $1.level }
    return HabitStats(streak: streak, best: best, events: events)
  }

  /// The levels a habit has: the ones its record reached, and whatever the server granted.
  public static func earnedLevels(_ habit: Habit, best: Int) -> Set<Int> {
    Set(achievementLevels.filter { best >= $0 }).union(habit.achievements ?? [])
  }

  /// The first level above the current streak.
  public static func nextGoal(streak: Int) -> Int? {
    achievementLevels.first { $0 > streak }
  }

  /// The first level the record has not reached (the dashed chip among the achievements).
  public static func nextUnearned(best: Int, earned: Set<Int>) -> Int? {
    achievementLevels.first { $0 > best && !earned.contains($0) }
  }

  /// The smallest level a mark made reachable: the record crossed it between the two states.
  public static func crossedLevel(bestBefore: Int, bestAfter: Int) -> Int? {
    achievementLevels.first { bestBefore < $0 && $0 <= bestAfter }
  }

  // MARK: Awards

  /// «Награды»: the newest achievements of at least `minLevel` across the habits.
  public static func awards(
    _ sources: [(id: String, title: String, stats: HabitStats)], minLevel: Int = awardMinimumLevel,
    limit: Int = 6
  ) -> [HabitAward] {
    sources.flatMap { source in
      source.stats.events.filter { $0.level >= minLevel }.map {
        HabitAward(habitID: source.id, title: source.title, level: $0.level, day: $0.day)
      }
    }
    .sorted {
      if $0.day != $1.day { return $0.day > $1.day }
      if $0.level != $1.level { return $0.level > $1.level }
      return $0.title < $1.title
    }
    .prefix(limit).map { $0 }
  }

  /// The habit that is closest to its next level.
  public static func closestGoal(_ sources: [(id: String, title: String, stats: HabitStats)])
    -> HabitGoal?
  {
    var closest: HabitGoal?
    for source in sources {
      guard let level = nextGoal(streak: source.stats.streak) else { continue }
      let remaining = level - source.stats.streak
      if closest == nil || remaining < closest!.remaining {
        closest = HabitGoal(
          habitID: source.id, title: source.title, level: level, remaining: remaining)
      }
    }
    return closest
  }

  // MARK: Counter step

  /// The step of the − / + buttons of a counted habit: a quarter litre for millilitres, else
  /// about an eighth of the goal rounded down to a round number, never below 1.
  public static func step(target: Int, unit: String?) -> Int {
    let unit = (unit ?? "").lowercased().trimmingCharacters(in: .whitespaces)
    if ["мл", "ml"].contains(unit), target >= 500 { return 250 }
    let wanted = Double(max(1, target)) / 8
    let round = [1, 2, 5, 10, 20, 25, 50, 100, 250, 500, 1000]
    return round.last { Double($0) <= wanted } ?? 1
  }
}
