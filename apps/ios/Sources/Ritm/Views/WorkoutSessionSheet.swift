import RitmCore
import SwiftUI

/// The details of one finished workout: a gradient card in the program's colour with the date and
/// the three numbers, one glass card per exercise (best set highlighted, ★ for a record set in
/// this workout), the habit line, «Повторить тренировку» and «Закрыть». Lists are lazy and rows
/// are plain stacks, so Dynamic Type simply makes them taller.
struct WorkoutSessionSheet: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let record: WorkoutRecord
  /// Starts the same program again (the screen that opened the sheet decides how).
  let repeatWorkout: (String) -> Void

  private var russian: Bool { store.language == .ru }
  private var program: WorkoutProgram? { store.workouts.program(record.programID) }
  private var name: String { record.programName.isEmpty ? store.text("Тренировка", "Workout") : record.programName }

  /// A program that was deleted keeps a steady colour of its own.
  private var colorIndex: Int {
    program?.colorIndex
      ?? record.programID.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % WorkoutProgram.colorCount }
  }

  /// The linked habit, when it was ticked on the day of this workout.
  private var tickedHabit: Habit? {
    guard let id = store.workouts.settings.linkedHabitID,
      let habit = store.habits.first(where: { $0.id == id && $0.archived != true }),
      HabitSchedule.isComplete(habit, on: HabitSchedule.dateKey(record.endedAt, timeZone: store.timeZone))
    else { return nil }
    return habit
  }

  var body: some View {
    let records = WorkoutRecords.recordSets(in: record, history: store.workouts.history)
    ScrollView {
      LazyVStack(spacing: 12) {
        header
        ForEach(record.exercises) { exercise in
          WorkoutExerciseResultCard(exercise: exercise, recordIndex: records[exercise.exerciseID])
        }
        if let habit = tickedHabit { habitLine(habit) }
        buttons
      }
      .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 24)
    }
    .background(RitmTheme.background)
    .presentationDetents([.large])
    .ritmSheetGrabber()
  }

  // MARK: Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        Text(String(name.first(where: { $0.isLetter || $0.isNumber }) ?? "•").uppercased())
          .ritmFont(20, weight: .bold)
          .frame(width: 48, height: 48)
          .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(name).ritmFont(20, weight: .bold, tracking: -0.03).lineLimit(2)
            .multilineTextAlignment(.leading)
            .accessibilityAddTraits(.isHeader)
          Text(WorkoutText.date(record.endedAt, language: store.language, year: true))
            .ritmFont(13).opacity(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) { stats }
        VStack(spacing: 8) { stats }
      }
    }
    .foregroundStyle(Color.white)
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background { WorkoutGradientSurface(colorIndex: colorIndex, radius: 26) }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder private var stats: some View {
    statTile(
      WorkoutText.duration(record.duration, russian: russian), store.text("Длительность", "Duration"))
    statTile(WorkoutText.kilograms(record.volume, russian: russian), store.text("Объём", "Volume"))
    statTile("\(record.setCount)", store.text("Подходов", "Sets"))
  }

  private func statTile(_ value: String, _ title: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(value).ritmFont(17, weight: .bold, tracking: -0.03).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.8)
      Text(title).ritmFont(11).opacity(0.85).lineLimit(1)
    }
    .padding(.horizontal, 12).padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  // MARK: Rest of the sheet

  private func habitLine(_ habit: Habit) -> some View {
    HStack(spacing: 10) {
      RitmSymbol("checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(WorkoutColors.income)
        .frame(width: 32, height: 32)
        .background(WorkoutPalette.incomeSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
      Text(store.text("Привычка «\(habit.title)» отмечена", "Habit “\(habit.title)” ticked"))
        .ritmFont(14, weight: .semibold).foregroundStyle(RitmTheme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(12)
    .background { RitmPanelBackground(radius: 18) }
    .accessibilityElement(children: .combine)
  }

  private var buttons: some View {
    VStack(spacing: 8) {
      if let program {
        Button {
          dismiss()
          repeatWorkout(program.id)
        } label: {
          Text(store.text("Повторить тренировку", "Repeat workout")).ritmFont(16, weight: .bold)
        }
        .buttonStyle(RitmPrimaryButtonStyle(minHeight: 52))
      }
      Button { dismiss() } label: {
        Text(store.text("Закрыть", "Close")).ritmFont(16, weight: .bold)
      }
      .buttonStyle(RitmSecondaryButtonStyle(minHeight: 52))
    }
    .padding(.top, 4)
  }
}

// MARK: - Exercise card

/// One exercise of a finished workout: name, muscle, its volume and the numbered sets.
private struct WorkoutExerciseResultCard: View {
  @Environment(RitmStore.self) private var store
  let exercise: WorkoutRecordExercise
  /// The set that was a personal record in that workout, if any.
  let recordIndex: Int?

  private var russian: Bool { store.language == .ru }

  var body: some View {
    let best = WorkoutRecords.bestSetIndex(exercise.sets)
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .leading, spacing: 6) {
          Text(exercise.name).ritmFont(16, weight: .bold, tracking: -0.02)
            .foregroundStyle(RitmTheme.text).multilineTextAlignment(.leading)
            .accessibilityAddTraits(.isHeader)
          if let muscle = store.workouts.library.muscle(of: exercise.exerciseID) {
            WorkoutMuscleChip(muscle: muscle)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .trailing, spacing: 0) {
          Text(WorkoutText.kilograms(exercise.volume, russian: russian))
            .ritmFont(14, weight: .bold).monospacedDigit().foregroundStyle(RitmTheme.text)
          Text(store.text("объём", "volume")).ritmFont(11).foregroundStyle(RitmTheme.muted)
        }
        .accessibilityElement(children: .combine)
      }
      .padding(.bottom, 8)
      ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
        setRow(
          index, set, isBest: index == best && (exercise.sets.count > 1 || index == recordIndex),
          isRecord: index == recordIndex)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background { RitmPanelBackground(radius: 22) }
    .accessibilityElement(children: .contain)
  }

  private func setRow(_ index: Int, _ set: WorkoutResultSet, isBest: Bool, isRecord: Bool) -> some View {
    let kg = russian ? "кг" : "kg"
    let text = "\(WorkoutFormat.weight(set.weight, comma: russian))\u{00A0}\(kg) × \(set.reps)"
    return HStack(spacing: 10) {
      Text("\(index + 1)").ritmFont(13, weight: .bold).monospacedDigit()
        .foregroundStyle(isBest ? RitmTheme.accentColor : RitmTheme.muted)
        .frame(minWidth: 22, alignment: .leading)
      Text(text).ritmFont(15, weight: isBest ? .bold : .medium).monospacedDigit()
        .foregroundStyle(RitmTheme.text)
      Spacer(minLength: 8)
      if isRecord { recordBadge }
    }
    .padding(.horizontal, 10).frame(minHeight: 42)
    .background {
      if isBest {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RitmTheme.soft)
          .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .strokeBorder(RitmTheme.accentColor.opacity(0.35), lineWidth: 1)
          }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      store.text("Подход \(index + 1)", "Set \(index + 1)") + ", " + text
        + (isBest ? store.text(", лучший", ", best") : "")
        + (isRecord ? store.text(", личный рекорд", ", personal record") : ""))
  }

  private var recordBadge: some View {
    HStack(spacing: 4) {
      RitmSymbol("star.fill").font(.system(size: 11))
      Text(store.text("Рекорд", "Record")).ritmFont(11, weight: .bold)
    }
    .foregroundStyle(WorkoutPalette.gold)
    .padding(.horizontal, 9).frame(minHeight: 24)
    .background(WorkoutPalette.gold.opacity(0.18), in: Capsule())
  }
}
