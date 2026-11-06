import Foundation
import RitmCore
import RitmSystem
import SwiftUI
import WidgetKit

/// One combined widget: today's confirmed tasks and scheduled habits. It has no API credential;
/// tapping a row opens its existing page, rather than pretending a server mutation was confirmed.
struct RitmDayHabitsWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WidgetSnapshotStore.kind, provider: DayHabitsProvider()) { entry in
      DayHabitsWidgetView(entry: entry)
        .containerBackground(.ultraThinMaterial, for: .widget)
    }
    .configurationDisplayName(systemText("Мой день и привычки", "My day & habits"))
    .description(systemText(
      "Дела на сегодня, ближайшее событие и привычки в одном виджете.",
      "Today's tasks, your next event and habits in one widget."))
    .supportedFamilies([.systemSmall, .systemMedium])
    .contentMarginsDisabled()
  }
}

private func systemText(_ ru: String, _ en: String) -> String {
  Locale.preferredLanguages.first?.hasPrefix("ru") == true ? ru : en
}

private struct DayHabitsEntry: TimelineEntry {
  let date: Date
  let snapshot: DayWidgetSnapshot?
  var placeholder = false
  var hasSharedContainer = true

  var validSnapshot: DayWidgetSnapshot? {
    guard let snapshot, snapshot.isValid(at: date) else { return nil }
    return snapshot
  }
  var russian: Bool {
    snapshot?.language == .ru
      || (snapshot == nil && Locale.preferredLanguages.first?.hasPrefix("ru") == true)
  }
  func text(_ ru: String, _ en: String) -> String { russian ? ru : en }
}

private struct DayHabitsProvider: TimelineProvider {
  func placeholder(in context: Context) -> DayHabitsEntry {
    .init(date: .now, snapshot: nil, placeholder: true)
  }

  func getSnapshot(in context: Context, completion: @escaping (DayHabitsEntry) -> Void) {
    completion(.init(date: .now, snapshot: WidgetSnapshotStore.read(),
                     placeholder: context.isPreview,
                     hasSharedContainer: WidgetSnapshotStore.container != nil))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<DayHabitsEntry>) -> Void) {
    let now = Date()
    let snapshot = WidgetSnapshotStore.read()
    let shared = WidgetSnapshotStore.container != nil
    guard let snapshot, snapshot.isValid(at: now) else {
      completion(Timeline(entries: [.init(date: now, snapshot: snapshot,
                                         hasSharedContainer: shared)],
                          policy: .after(now.addingTimeInterval(15 * 60))))
      return
    }
    let entries = snapshot.timelineDates(after: now).map {
      DayHabitsEntry(date: $0, snapshot: snapshot, hasSharedContainer: shared)
    }
    // The final entry clears yesterday's values at midnight/session expiry. Only the app can
    // fetch tomorrow's authenticated data; WidgetKit controls the actual refresh scheduling.
    completion(Timeline(entries: entries, policy: .after(snapshot.validUntil)))
  }
}

private struct DayHabitsWidgetView: View {
  let entry: DayHabitsEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    Group {
      if let snapshot = entry.validSnapshot, !entry.placeholder {
        ReadyDayWidget(snapshot: snapshot, now: entry.date, small: family == .systemSmall)
      } else if entry.placeholder {
        WidgetGalleryPlaceholder(small: family == .systemSmall, russian: entry.russian)
      } else {
        EmptyDayWidget(entry: entry)
      }
    }
    .padding(14)
    .widgetURL(URL(string: "ritm://open/day"))
    .privacySensitive()
  }
}

private struct ReadyDayWidget: View {
  let snapshot: DayWidgetSnapshot
  let now: Date
  let small: Bool

  private func text(_ ru: String, _ en: String) -> String {
    snapshot.language == .ru ? ru : en
  }

  private var calendarSubtitle: String {
    if let event = snapshot.nextEvent(at: now) {
      return "\(event.title), \(event.timeLabel)"
    }
    switch snapshot.calendarState {
    case .ready: return text("Больше событий нет", "No more events")
    case .partial: return text("Часть расписания", "Partial schedule")
    case .unavailable: return text("Обновите расписание", "Refresh schedule")
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: small ? 6 : 7) {
      HStack(spacing: 8) {
        WidgetCalendarMark(date: now, timeZone: snapshot.timeZone,
                           language: snapshot.language)
        VStack(alignment: .leading, spacing: 1) {
          Text(text("Мой день", "My day"))
            .font(.system(size: 13, weight: .semibold)).tracking(-0.2).lineLimit(1)
          if !small {
            Text(calendarSubtitle)
              .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
          }
        }
        Spacer(minLength: 0)
        if !small { RitmSystemMark(size: 18) }
      }
      .frame(height: 28)

      if small {
        smallContent
      } else {
        mediumContent
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var smallContent: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(calendarSubtitle)
        .font(.system(size: 10, weight: .medium)).lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
      HStack(spacing: 4) {
        Text(text("Дела", "Tasks") + " \(snapshot.tasksCompleted)/\(snapshot.tasksTotal)")
        Spacer(minLength: 0)
        Text(text("Привычки", "Habits") + " \(snapshot.habitsCompleted)/\(snapshot.habitsPlanned)")
      }
      .font(.system(size: 8)).foregroundStyle(.secondary).monospacedDigit()
      habitGroup
    }
  }

  private var mediumContent: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 0) {
        if snapshot.tasks.isEmpty {
          Text(text("На сегодня дел нет", "No tasks for today"))
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        } else {
          ForEach(Array(snapshot.tasks.prefix(2))) { task in
            Link(destination: task.destination) {
              HStack(spacing: 7) {
                Image(systemName: task.completed == nil ? "questionmark.circle"
                      : task.completed == true ? "checkmark.square.fill" : "square")
                  .font(.system(size: 16, weight: .regular))
                  .foregroundStyle(task.completed == true ? .primary : .secondary)
                Text(task.title)
                  .font(.system(size: 11, weight: .medium)).lineLimit(2)
                  .strikethrough(task.completed == true)
                  .foregroundStyle(task.completed == true ? .secondary : .primary)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
              .contentShape(Rectangle())
            }
            .accessibilityLabel(task.title + ", " + (task.completed == nil
              ? text("статус неизвестен", "status unknown") : task.completed == true
              ? text("выполнено", "complete") : text("не выполнено", "incomplete")))
            .accessibilityHint(text("Открыть Мой день в Ritm", "Open My day in Ritm"))
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Rectangle().fill(.primary.opacity(0.1)).frame(width: 0.5, height: 70)

      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text(text("Привычки", "Habits"))
          Spacer(minLength: 2)
          Text("\(snapshot.habitsCompleted)/\(snapshot.habitsPlanned)")
            .fontWeight(.medium).monospacedDigit()
        }
        .font(.system(size: 10)).foregroundStyle(.secondary)
        habitGroup
      }
      .frame(width: 132)
    }
    .frame(maxHeight: .infinity)
  }

  @ViewBuilder private var habitGroup: some View {
    if snapshot.habits.isEmpty {
      Text(text("Нет запланированных привычек", "No habits planned"))
        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
    } else {
      HStack(alignment: .top, spacing: 0) {
        ForEach(snapshot.habits) { habit in
          Link(destination: habit.destination) {
            VStack(spacing: 1) {
              ZStack {
                Circle().fill(.primary.opacity(habit.completed ? 0.17 : 0.06))
                  .overlay { Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.75) }
                  .frame(width: 36, height: 36)
                Image(systemName: habit.completed ? "checkmark" : habit.icon.systemSymbol)
                  .font(.system(size: 16, weight: habit.completed ? .semibold : .regular))
              }
              .frame(width: 44, height: 44)
              Text(habit.title).font(.system(size: 8)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail).frame(width: 44)
            }
            .contentShape(Rectangle())
          }
          .frame(maxWidth: .infinity)
          .accessibilityLabel(habit.title + ", " + (habit.completed
            ? text("выполнено", "complete") : "\(habit.progress)/\(habit.target)"))
          .accessibilityHint(text("Открыть привычки в Ritm", "Open habits in Ritm"))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct WidgetCalendarMark: View {
  let date: Date
  let timeZone: String
  let language: Language

  private var calendar: Calendar {
    var result = Calendar(identifier: .gregorian)
    result.timeZone = TimeZone(identifier: timeZone) ?? .gmt
    return result
  }
  private var month: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language == .ru ? "ru_RU" : "en_US")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "MMM"
    return String(formatter.string(from: date).replacingOccurrences(of: ".", with: "").prefix(3))
      .uppercased()
  }
  var body: some View {
    VStack(spacing: 0) {
      Text(month).font(.system(size: 7, weight: .medium))
      Text("\(calendar.component(.day, from: date))")
        .font(.system(size: 16, weight: .semibold, design: .rounded)).tracking(-0.7)
    }
    .frame(width: 28, height: 28)
    .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    .accessibilityHidden(true)
  }
}

private struct EmptyDayWidget: View {
  let entry: DayHabitsEntry
  var body: some View {
    Link(destination: URL(string: "ritm://open/day")!) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 7) {
          RitmSystemMark(size: 24)
          Text(entry.text("Мой день", "My day"))
            .font(.system(size: 13, weight: .semibold))
        }
        Text(entry.text("Откройте Ritm", "Open Ritm"))
          .font(.system(size: 15, weight: .semibold))
        Text(entry.snapshot != nil
          ? entry.text("Обновите дела и привычки на сегодня.", "Refresh today's tasks and habits.")
          : entry.hasSharedContainer
          ? entry.text("Войдите и синхронизируйте данные.", "Sign in and sync your data.")
          : entry.text("Общие данные виджета ещё недоступны.", "Shared widget data is unavailable."))
          .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .contentShape(Rectangle())
    }
  }
}

private struct WidgetGalleryPlaceholder: View {
  let small: Bool
  let russian: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 7) {
        RitmSystemMark(size: 24)
        Text(russian ? "Мой день" : "My day").font(.system(size: 13, weight: .semibold))
      }
      HStack(spacing: 12) {
        if !small {
          VStack(alignment: .leading, spacing: 12) {
            Capsule().fill(.primary.opacity(0.1)).frame(height: 7)
            Capsule().fill(.primary.opacity(0.1)).frame(height: 7)
          }
          .frame(maxWidth: .infinity)
        }
        HStack(spacing: 8) {
          ForEach(0..<3, id: \.self) { _ in
            Circle().fill(.primary.opacity(0.06))
              .overlay { Circle().strokeBorder(.primary.opacity(0.1), lineWidth: 0.75) }
              .frame(width: 32, height: 32)
          }
        }
      }
      Text(russian ? "Ваши дела и привычки" : "Your tasks and habits")
        .font(.system(size: 10)).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityLabel(russian ? "Предпросмотр виджета, без данных" : "Widget preview, no data")
  }
}

private extension HabitIcon {
  var systemSymbol: String {
    switch self {
    case .sparkles: return "sparkles"
    case .book: return "book"
    case .activity: return "waveform.path.ecg"
    case .droplet: return "drop"
    case .moon: return "moon"
    case .target: return "target"
    }
  }
}
