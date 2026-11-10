import RitmCore
import SwiftUI

/// `.a2-hi`: a finished workout in a list: letter tile, program, «Вчера · 52 мин», the volume.
struct WorkoutHistoryRow: View {
  @Environment(RitmStore.self) private var store
  let record: WorkoutRecord
  let open: () -> Void

  var body: some View {
    let russian = store.language == .ru
    Button(action: open) {
      HStack(spacing: 10) {
        WorkoutLetterTile(name: record.programName)
        VStack(alignment: .leading, spacing: 0) {
          Text(record.programName.isEmpty ? store.text("Тренировка", "Workout") : record.programName)
            .ritmFont(13.5, weight: .semibold, tracking: -0.02).foregroundStyle(RitmTheme.text)
            .lineLimit(1)
          Text(
            WorkoutText.relativeDay(
              record.endedAt, today: store.today, timeZone: store.timeZone, language: store.language)
              + " · " + WorkoutText.duration(record.duration, russian: russian)
          )
          .ritmFont(11).foregroundStyle(RitmTheme.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Text(WorkoutText.kilograms(record.volume, russian: russian))
          .ritmFont(13, weight: .bold).foregroundStyle(RitmTheme.text).monospacedDigit()
      }
      .padding(.horizontal, 12).padding(.vertical, 9)
      .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
      .background { RitmPanelBackground(radius: 16) }
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
  }
}

/// The history screen: every finished workout, newest first.
struct WorkoutHistoryView: View {
  @Environment(RitmStore.self) private var store
  let go: (WorkoutScreen) -> Void
  let start: (String) -> Void
  @State private var opened: WorkoutRecord?

  var body: some View {
    WorkoutPage(
      header: {
        RitmPageHeading(title: store.text("История", "History"), gap: 12) {
          WorkoutRoundButton(symbol: "chevron.left", label: store.text("Назад", "Back"), size: 44) {
            go(.home)
          }
        }
      },
      content: {
        let records = store.workouts.history.records
        if records.isEmpty {
          WorkoutEmptyText(text: store.text("Пока нет завершённых тренировок.", "No finished workouts yet."))
            .ritmPageReveal(index: 0)
        } else {
          LazyVStack(spacing: 6) {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
              WorkoutHistoryRow(record: record) { opened = record }
                .ritmPageReveal(index: min(index, 7))
            }
          }
        }
      }
    )
    .sheet(item: $opened) { WorkoutSessionSheet(record: $0, repeatWorkout: start) }
  }
}

/// `.fin`: «Тренировка завершена» with the time, the weight lifted and the sets done.
struct WorkoutSummaryView: View {
  @Environment(RitmStore.self) private var store
  let record: WorkoutRecord?
  let go: (WorkoutScreen) -> Void

  var body: some View {
    let russian = store.language == .ru
    VStack(spacing: 12) {
      Spacer(minLength: 0)
      RitmSymbol("checkmark").font(.system(size: 38, weight: .semibold))
        .foregroundStyle(WorkoutColors.income)
        .frame(width: 76, height: 76)
        .background(WorkoutPalette.incomeSoft, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.bottom, 8)
        .accessibilityHidden(true)
      Text(store.text("Тренировка завершена", "Workout finished"))
        .ritmFont(26, weight: .bold, tracking: -0.04).foregroundStyle(RitmTheme.text)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)
      if let record {
        let sets = record.exercises.reduce(0) { $0 + $1.sets.count }
        Text(
          WorkoutClock.format(seconds: Int(record.duration)) + " · "
            + WorkoutText.kilograms(record.volume, russian: russian) + " · "
            + store.text(
              "\(sets) " + WorkoutText.plural(sets, "подход", "подхода", "подходов"), "\(sets) sets")
        )
        .ritmFont(14.5).foregroundStyle(RitmTheme.muted).monospacedDigit()
        .padding(.bottom, 18)
      }
      Button { go(.home) } label: {
        Text(store.text("Готово", "Done")).ritmFont(16, weight: .bold)
      }
      .buttonStyle(RitmPrimaryButtonStyle(minHeight: 56))
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 32)
    .frame(maxWidth: 700, maxHeight: .infinity)
    .frame(maxWidth: .infinity)
  }
}
