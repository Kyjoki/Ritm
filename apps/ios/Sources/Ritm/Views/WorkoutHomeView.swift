import RitmCore
import SwiftUI

/// The programs list: compact rows (tap to start, ⠿ to reorder, pencil to edit), the workout in
/// progress, and the latest finished workouts.
struct WorkoutHomeView: View {
  @Environment(RitmStore.self) private var store
  let go: (WorkoutScreen) -> Void
  @State private var opened: WorkoutRecord?

  private var workouts: WorkoutStore { store.workouts }
  private var russian: Bool { store.language == .ru }

  var body: some View {
    WorkoutPage(
      title: store.text("Тренировки", "Workouts"),
      action: {
        WorkoutHeaderButton(
          symbol: "clock.arrow.circlepath", label: store.text("История тренировок", "Workout history")
        ) { go(.history) }
      },
      content: {
        VStack(alignment: .leading, spacing: 12) {
          if let session = workouts.session { activeCard(session).ritmPageReveal(index: 0) }
          programs.ritmPageReveal(index: 1)
          recent.ritmPageReveal(index: 2)
        }
      }
    )
    .sheet(item: $opened) { WorkoutRecordSheet(record: $0) }
  }

  // MARK: Active workout

  private func activeCard(_ session: WorkoutSession) -> some View {
    RitmCard(padding: 14) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(store.text("Идёт тренировка", "Workout in progress"))
            .ritmFont(11, weight: .bold).foregroundStyle(RitmTheme.accentColor)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RitmTheme.soft, in: Capsule())
            .overlay { Capsule().strokeBorder(RitmTheme.line, lineWidth: 1) }
          Text(session.programName).ritmFont(16, weight: .semibold, tracking: -0.03)
            .foregroundStyle(RitmTheme.text).lineLimit(2)
          HStack(spacing: 0) {
            Text(store.text("Выполнено подходов: ", "Sets done: "))
            RitmCountText(session.doneSets) { "\($0)" }.fontWeight(.bold)
            Text(store.text(" из ", " of ") + "\(session.totalSets)")
          }
          .ritmText(.body).foregroundStyle(RitmTheme.muted)
        }
        Spacer(minLength: 8)
        Button { go(.active) } label: {
          Text(store.text("Продолжить", "Resume")).workoutButtonFont()
        }
        .buttonStyle(RitmPrimaryButtonStyle(minHeight: 48))
        .fixedSize()
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: 23, style: .circular).strokeBorder(RitmTheme.accentColor, lineWidth: 1)
        .allowsHitTesting(false)
    }
  }

  // MARK: Programs

  @ViewBuilder private var programs: some View {
    let list = workouts.library.programs
    VStack(alignment: .leading, spacing: 8) {
      WorkoutSectionLabel(title: store.text("Программы", "Programs"))
      if list.isEmpty {
        WorkoutEmptyText(text: store.text("Программ пока нет. Добавьте первую.", "No programs yet. Add the first one."))
      } else {
        WorkoutReorderList(
          items: list, spacing: 8, cornerRadius: 20, handleSize: 20,
          onMove: { workouts.moveProgram(from: $0, to: $1) }
        ) { program, handle in
          let index = list.firstIndex { $0.id == program.id } ?? 0
          WorkoutProgramRow(
            program: program, handle: handle,
            start: { start(program) }, edit: { go(.editor(program.id)) },
            move: { delta in
              let target = index + delta
              guard list.indices.contains(target) else { return }
              withAnimation(RitmMotion.easeOut(0.22)) { workouts.moveProgram(from: index, to: target) }
            })
        }
      }
      Button {
        addProgram()
      } label: {
        Label { Text(store.text("Добавить программу", "Add program")) } icon: { RitmSymbol("plus") }
          .workoutButtonFont()
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(RitmSecondaryButtonStyle(minHeight: 48))
    }
  }

  private func addProgram() {
    let number = workouts.library.programs.count + 1
    let id = workouts.addProgram(name: store.text("Программа \(number)", "Program \(number)"))
    go(.editor(id))
  }

  private func start(_ program: WorkoutProgram) {
    switch workouts.startWorkout(programID: program.id, language: store.language) {
    case .started: go(.active)
    case .alreadyActive:
      store.toasts.show(
        store.text(
          "Сначала завершите или отмените текущую тренировку",
          "Finish or cancel the current workout first"))
    case .empty:
      store.toasts.show(
        store.text(
          "Добавьте в программу хотя бы одно упражнение", "Add at least one exercise to the program"))
    }
  }

  // MARK: Latest workouts

  @ViewBuilder private var recent: some View {
    let records = Array(workouts.history.records.prefix(3))
    VStack(alignment: .leading, spacing: 8) {
      WorkoutSectionLabel(
        title: store.text("Последние тренировки", "Latest workouts"),
        link: store.text("Вся история", "All history")
      ) { go(.history) }
      if records.isEmpty {
        WorkoutEmptyText(text: store.text("Пока нет завершённых тренировок.", "No finished workouts yet."))
      }
      ForEach(records) { record in
        WorkoutHistoryRow(record: record) { opened = record }
      }
    }
  }
}

/// One program in the list. The whole middle is the start button; the handle only reorders.
private struct WorkoutProgramRow: View {
  @Environment(RitmStore.self) private var store
  let program: WorkoutProgram
  let handle: WorkoutDragHandle
  let start: () -> Void
  let edit: () -> Void
  let move: (Int) -> Void

  private var badge: String {
    program.name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "•"
  }

  private var summary: String {
    let russian = store.language == .ru
    let names = program.items
      .map { store.workouts.exerciseName($0.exerciseID, language: store.language) }
      .joined(separator: ", ")
    let counts =
      russian
      ? "\(program.items.count) упр. · \(program.totalSets) подх."
      : "\(program.items.count) ex. · \(program.totalSets) sets"
    return names.isEmpty ? counts : counts + " · " + names
  }

  var body: some View {
    HStack(spacing: 2) {
      handle.frame(width: 30)
      Button(action: start) {
        HStack(spacing: 10) {
          Text(badge)
            .ritmFont(16, weight: .bold)
            .foregroundStyle(RitmTheme.accentColor)
            .frame(width: 38, height: 38)
            .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 12, style: .circular))
          VStack(alignment: .leading, spacing: 0) {
            Text(program.name.isEmpty ? store.text("Без названия", "Untitled") : program.name)
              .ritmFont(14.5, weight: .semibold, tracking: -0.03).foregroundStyle(RitmTheme.text).lineLimit(1)
            Text(summary).ritmFont(11.5).foregroundStyle(RitmTheme.muted).lineLimit(1)
          }
          Spacer(minLength: 4)
          RitmSymbol("play.fill").font(.system(size: 14)).foregroundStyle(RitmTheme.accentColor)
        }
        .padding(.leading, 2).padding(.trailing, 6)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
      }
      .buttonStyle(RitmPressStyle())
      .accessibilityLabel(store.text("Начать тренировку «\(program.name)»", "Start workout “\(program.name)”"))
      WorkoutIconButton(
        symbol: "pencil", label: store.text("Изменить программу «\(program.name)»", "Edit program “\(program.name)”"),
        size: 16, action: edit)
    }
    .padding(.leading, 6).padding(.trailing, 4).padding(.vertical, 4)
    .frame(minHeight: 60)
    .background { RitmPanelBackground(radius: 20) }
    .accessibilityElement(children: .contain)
    .accessibilityAction(named: store.text("Вверх", "Move up")) { move(-1) }
    .accessibilityAction(named: store.text("Вниз", "Move down")) { move(1) }
  }
}

/// A finished workout in a list: date, program, and the total weight counting up.
struct WorkoutHistoryRow: View {
  @Environment(RitmStore.self) private var store
  let record: WorkoutRecord
  let open: () -> Void

  var body: some View {
    let russian = store.language == .ru
    Button(action: open) {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(WorkoutText.date(record.endedAt, language: store.language))
            .ritmFont(13.5, weight: .bold).foregroundStyle(RitmTheme.text)
          Text(
            "\(record.programName) · "
              + WorkoutText.exercises(record.exercises.count, russian: russian)
          )
          .ritmFont(11.5).foregroundStyle(RitmTheme.muted).lineLimit(1)
        }
        Spacer(minLength: 4)
        RitmCountText(record.volume) { WorkoutText.kilograms($0, russian: russian) }
          .ritmFont(13, weight: .bold).foregroundStyle(RitmTheme.text)
        RitmSymbol("chevron.right").font(.system(size: 13, weight: .semibold))
          .foregroundStyle(RitmTheme.muted)
          .frame(width: 16)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 12).padding(.vertical, 8)
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
      .background { RitmPanelBackground(radius: 18) }
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
  }
}

/// The history screen: every finished workout, newest first.
struct WorkoutHistoryView: View {
  @Environment(RitmStore.self) private var store
  let go: (WorkoutScreen) -> Void
  @State private var opened: WorkoutRecord?

  var body: some View {
    WorkoutPage(
      title: store.text("История", "History"),
      action: {
        WorkoutHeaderButton(symbol: "chevron.left", label: store.text("К программам", "To programs")) {
          go(.home)
        }
      },
      content: {
        let records = store.workouts.history.records
        if records.isEmpty {
          WorkoutEmptyText(text: store.text("Пока нет завершённых тренировок.", "No finished workouts yet."))
            .ritmPageReveal(index: 0)
        } else {
          LazyVStack(spacing: 8) {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
              WorkoutHistoryRow(record: record) { opened = record }
                .ritmPageReveal(index: min(index, 7))
            }
          }
        }
      }
    )
    .sheet(item: $opened) { WorkoutRecordSheet(record: $0) }
  }
}

/// The details of one finished workout.
struct WorkoutRecordSheet: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let record: WorkoutRecord

  var body: some View {
    let russian = store.language == .ru
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Text(WorkoutText.date(record.endedAt, language: store.language, year: true))
            .ritmText(.sectionTitle).foregroundStyle(RitmTheme.text)
            .accessibilityAddTraits(.isHeader)
          Spacer()
          Button(store.text("Закрыть", "Close")) { dismiss() }
            .buttonStyle(RitmTextButtonStyle(size: 13))
        }
        Text(
          "\(record.programName) · \(WorkoutText.duration(record.duration, russian: russian)) · "
            + store.text("объём ", "volume ") + WorkoutText.kilograms(record.volume, russian: russian)
        )
        .ritmText(.body).foregroundStyle(RitmTheme.muted)
        ForEach(record.exercises) { exercise in
          VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name).ritmFont(14, weight: .semibold).foregroundStyle(RitmTheme.text)
            ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
              HStack(spacing: 12) {
                Text("\(index + 1)").foregroundStyle(RitmTheme.muted).frame(width: 18, alignment: .leading)
                Text(
                  "\(WorkoutFormat.weight(set.weight, comma: russian))\u{00A0}\(russian ? "кг" : "kg") × \(set.reps)"
                )
                Spacer()
              }
              .ritmFont(13).monospacedDigit().foregroundStyle(RitmTheme.text)
              .frame(minHeight: 32)
              Divider()
            }
          }
        }
      }
      .padding(20)
    }
    .background(RitmTheme.background)
    .presentationDetents([.medium, .large])
  }
}
