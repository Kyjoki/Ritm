import RitmCore
import SwiftUI

/// What the record sheet is editing: an existing record or a new one.
struct WorkoutRecordTarget: Identifiable, Equatable {
  let card: WorkoutRecordCard?
  var id: String { card?.exerciseID ?? "new" }
}

/// «Тренировки»: the week at a glance, the programs, the records and the latest workouts.
struct WorkoutHomeView: View {
  @Environment(RitmStore.self) private var store
  let go: (WorkoutScreen) -> Void
  let start: (String) -> Void
  @State private var showingSettings = false
  @State private var recordTarget: WorkoutRecordTarget?
  @State private var opened: WorkoutRecord?

  private var workouts: WorkoutStore { store.workouts }
  private var russian: Bool { store.language == .ru }

  /// The habit that finished workouts tick, when it still exists and is not archived.
  private var linkedHabit: Habit? {
    guard let id = workouts.settings.linkedHabitID else { return nil }
    return store.habits.first { $0.id == id && $0.archived != true }
  }

  var body: some View {
    WorkoutPage(
      header: {
        RitmPageHeading(title: store.text("Тренировки", "Workouts"), gap: 12) {
          WorkoutRoundButton(
            symbol: "slider.horizontal.3",
            label: store.text("Настройки тренировок", "Workout settings")
          ) { showingSettings = true }
        }
      },
      content: {
        VStack(alignment: .leading, spacing: 0) {
          if let session = workouts.session {
            WorkoutResumeBanner(session: session) { go(.active) }
              .padding(.bottom, 10).ritmPageReveal(index: 0)
          }
          habitChip.padding(.bottom, 8).ritmPageReveal(index: 1)
          hero.ritmPageReveal(index: 2)
          WorkoutSectionHeader(title: store.text("Программы", "Programs"))
          WorkoutProgramsRow(
            programs: workouts.library.programs, russian: russian,
            open: { go(.program($0)) }, start: start, add: addProgram
          )
          .ritmPageReveal(index: 3)
          WorkoutSectionHeader(title: store.text("Рекорды", "Records"))
          WorkoutRecordsRow(
            cards: workouts.recordCards,
            edit: { recordTarget = WorkoutRecordTarget(card: $0) },
            add: { recordTarget = WorkoutRecordTarget(card: nil) }
          )
          .ritmPageReveal(index: 4)
          history.ritmPageReveal(index: 5)
        }
      }
    )
    .sheet(isPresented: $showingSettings) { WorkoutSettingsSheet() }
    .sheet(item: $recordTarget) { WorkoutRecordSheet(target: $0) }
    .sheet(item: $opened) { WorkoutSessionSheet(record: $0) }
  }

  // MARK: Pieces

  private var habitChip: some View {
    Button {
      showingSettings = true
    } label: {
      HStack(spacing: 6) {
        RitmSymbol("link").font(.system(size: 13))
        Text(
          linkedHabit.map { $0.title + " · " + store.text("привычка", "habit") }
            ?? store.text("Без привычки", "No habit")
        )
        .lineLimit(1)
      }
      .ritmFont(12, weight: .bold).foregroundStyle(RitmTheme.accentColor)
      .padding(.horizontal, 12).frame(height: 28)
      .background(RitmTheme.soft, in: Capsule())
      .overlay { Capsule().strokeBorder(WorkoutPalette.stroke, lineWidth: 1) }
      .frame(minHeight: 44)
      .contentShape(Capsule())
    }
    .buttonStyle(RitmPressStyle())
    .padding(.vertical, -8)
    .accessibilityLabel(store.text("Связь с привычкой", "Habit link"))
  }

  private var hero: some View {
    // A linked habit that has not loaded yet shows no numbers; the 4-a-week goal is only for
    // when no habit is linked at all.
    let week =
      workouts.settings.linkedHabitID != nil && linkedHabit == nil
      ? WorkoutStats.pendingWeek(today: store.today)
      : WorkoutStats.week(
        habit: linkedHabit, history: workouts.history, today: store.today, timeZone: store.timeZone)
    let trend = WorkoutStats.volumeTrend(
      workouts.history, today: store.today, timeZone: store.timeZone)
    let streak = WorkoutStats.streakWeeks(
      workouts.history, today: store.today, timeZone: store.timeZone)
    return WorkoutHeroCard(week: week, volume: trend.volume, percent: trend.percent, streak: streak)
  }

  @ViewBuilder private var history: some View {
    let records = Array(workouts.history.records.prefix(4))
    WorkoutSectionHeader(
      title: store.text("История", "History"), link: store.text("Вся история", "All history")
    ) { go(.history) }
    if records.isEmpty {
      WorkoutEmptyText(text: store.text("Пока нет завершённых тренировок.", "No finished workouts yet."))
    } else {
      VStack(spacing: 6) {
        ForEach(records) { record in
          WorkoutHistoryRow(record: record) { opened = record }
        }
      }
    }
  }

  private func addProgram() {
    go(.editor(id: WorkoutID.make(), isNew: true))
  }
}

// MARK: - Banner

/// `.a2-cont`: «Продолжить тренировку», the running workout as a lit capsule.
private struct WorkoutResumeBanner: View {
  @Environment(RitmStore.self) private var store
  let session: WorkoutSession
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 1) {
          Text(store.text("Продолжить тренировку", "Resume workout").uppercased())
            .ritmFont(11, weight: .bold, tracking: 0.06).opacity(0.75)
          Text(session.programName).ritmFont(15.5, weight: .bold, tracking: -0.03).lineLimit(1)
          HStack(spacing: 0) {
            Text(
              store.text(
                "\(session.doneSets) из \(session.totalSets) подходов · ",
                "\(session.doneSets) of \(session.totalSets) sets · "))
            TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
              Text(WorkoutClock.elapsed(from: session.startedAt, now: context.date)).monospacedDigit()
            }
          }
          .ritmFont(12).opacity(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        RitmSymbol("play.fill").font(.system(size: 18))
          .frame(width: 44, height: 44)
          .background(Color.white.opacity(0.26), in: Circle())
      }
      .foregroundStyle(RitmTheme.ctaInk)
      .padding(.vertical, 12).padding(.leading, 14).padding(.trailing, 12)
      .background {
        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(RitmTheme.ctaGradient)
          .shadow(color: RitmGlassTokens.ctaGlow, radius: 9, y: 8)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
  }
}
