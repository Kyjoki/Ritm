import RitmCore
import SwiftUI

/// A program: the coloured header with its numbers, the exercises with sets × reps and the last
/// weight, «Изменить», and the big «Начать тренировку».
struct WorkoutProgramView: View {
  @Environment(RitmStore.self) private var store
  let programID: String
  let go: (WorkoutScreen) -> Void
  let start: (String) -> Void

  private var workouts: WorkoutStore { store.workouts }
  private var russian: Bool { store.language == .ru }

  var body: some View {
    if let program = workouts.program(programID) {
      page(program)
    } else {
      Color.clear.onAppear { go(.home) }
    }
  }

  private func page(_ program: WorkoutProgram) -> some View {
    let running = workouts.session?.programID == program.id
    return WorkoutPage(
      header: { header(program) },
      bar: { startButton(program, running: running) },
      content: {
        VStack(alignment: .leading, spacing: 0) {
          hero(program).ritmPageReveal(index: 0)
          WorkoutSectionHeader(title: store.text("Упражнения", "Exercises"))
          if program.items.isEmpty {
            WorkoutEmptyText(
              text: store.text("В программе пока нет упражнений.", "No exercises in this program yet."))
          } else {
            VStack(spacing: 0) {
              ForEach(Array(program.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Rectangle().fill(RitmTheme.line).frame(height: 1) }
                row(item, number: index + 1)
              }
            }
            .padding(.vertical, 4)
            .background { RitmPanelBackground(radius: 22) }
            .ritmPageReveal(index: 1)
          }
          Color.clear.frame(height: 80)
        }
      }
    )
  }

  // MARK: Header and hero

  private func header(_ program: WorkoutProgram) -> some View {
    HStack(spacing: 10) {
      WorkoutRoundButton(symbol: "chevron.left", label: store.text("Назад", "Back")) { go(.home) }
      Text(store.text("Программа", "Program"))
        .ritmFont(16, weight: .bold, tracking: -0.03).foregroundStyle(RitmTheme.text)
        .frame(maxWidth: .infinity)
        .accessibilityAddTraits(.isHeader)
      Button {
        go(.editor(id: program.id, isNew: false))
      } label: {
        HStack(spacing: 6) {
          RitmSymbol("pencil").font(.system(size: 15))
          Text(store.text("Изменить", "Edit")).ritmFont(13, weight: .bold)
        }
        .foregroundStyle(RitmTheme.accentColor)
        .padding(.horizontal, 14).frame(height: 38)
        .ritmGlass(in: Capsule(), interactive: true)
        .frame(minHeight: 44)
        .contentShape(Capsule())
      }
      .buttonStyle(RitmGlassButtonStyle())
    }
    .padding(.bottom, 10)
  }

  private func hero(_ program: WorkoutProgram) -> some View {
    let muscles = muscles(of: program)
    return VStack(alignment: .leading, spacing: 0) {
      Text(String(program.name.first(where: { $0.isLetter || $0.isNumber }) ?? "•").uppercased())
        .ritmFont(20, weight: .bold)
        .frame(width: 46, height: 46)
        .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
      Text(program.name.isEmpty ? store.text("Без названия", "Untitled") : program.name)
        .ritmFont(28, weight: .bold, tracking: -0.045)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 14).padding(.bottom, 10)
        .accessibilityAddTraits(.isHeader)
      if !muscles.isEmpty {
        HStack(spacing: 6) {
          ForEach(muscles, id: \.self) { muscle in
            Text(muscle.title(language: store.language))
              .ritmFont(11.5, weight: .semibold)
              .padding(.horizontal, 10).frame(height: 24)
              .background(Color.white.opacity(0.2), in: Capsule())
          }
        }
      }
      HStack(spacing: 8) {
        metric("≈\(program.estimatedMinutes)", store.text("минут", "minutes"))
        metric("\(program.items.count)", store.text("упражнений", "exercises"))
        metric("\(program.totalSets)", store.text("подходов", "sets"))
      }
      .padding(.top, 16)
      Text(store.text("Последний раз · ", "Last time · ") + lastDone(program))
        .ritmFont(12.5).opacity(0.85).padding(.top, 12)
    }
    .foregroundStyle(Color.white)
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background { WorkoutGradientSurface(colorIndex: program.colorIndex, radius: 28) }
  }

  private func metric(_ value: String, _ title: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(value).ritmFont(20, weight: .bold, tracking: -0.04).lineLimit(1)
      Text(title).ritmFont(11).opacity(0.8).lineLimit(1).minimumScaleFactor(0.8)
    }
    .padding(.horizontal, 10).padding(.vertical, 9)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  /// Up to three muscle groups, in the order of the exercises.
  private func muscles(of program: WorkoutProgram) -> [WorkoutMuscle] {
    var seen: [WorkoutMuscle] = []
    for item in program.items {
      if let muscle = workouts.library.muscle(of: item.exerciseID), !seen.contains(muscle) {
        seen.append(muscle)
      }
    }
    return Array(seen.prefix(3))
  }

  private func lastDone(_ program: WorkoutProgram) -> String {
    guard let record = workouts.history.records.first(where: { $0.programID == program.id }) else {
      return store.text("ещё не было", "not yet")
    }
    return WorkoutText.relativeDay(
      record.endedAt, today: store.today, timeZone: store.timeZone, language: store.language
    ).lowercased()
  }

  // MARK: Exercises

  private func row(_ item: WorkoutProgramItem, number: Int) -> some View {
    let name = workouts.exerciseName(item.exerciseID, language: store.language)
    return HStack(spacing: 12) {
      Text("\(number)")
        .ritmFont(12.5, weight: .bold).foregroundStyle(RitmTheme.accentColor)
        .frame(width: 24, height: 24)
        .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      VStack(alignment: .leading, spacing: 4) {
        Text(name).ritmFont(14.5, weight: .semibold, tracking: -0.02).foregroundStyle(RitmTheme.text)
          .fixedSize(horizontal: false, vertical: true)
        if let muscle = workouts.library.muscle(of: item.exerciseID) { WorkoutMuscleChip(muscle: muscle) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .trailing, spacing: 0) {
        Text("\(item.sets) × \(item.reps)").ritmFont(14.5, weight: .bold).foregroundStyle(RitmTheme.text)
          .monospacedDigit()
        Text(lastWeight(item.exerciseID)).ritmFont(11.5).foregroundStyle(RitmTheme.muted)
      }
    }
    .padding(.horizontal, 14).padding(.vertical, 11)
    .accessibilityElement(children: .combine)
  }

  /// The top weight of the last time: «80 кг», «свой вес» for bodyweight, «—» when never done.
  private func lastWeight(_ exerciseID: String) -> String {
    guard let last = workouts.history.lastResult(exerciseID: exerciseID) else { return "—" }
    let top = last.sets.map(\.weight).max() ?? 0
    guard top > 0 else { return store.text("свой вес", "bodyweight") }
    return WorkoutFormat.weight(top, comma: russian) + "\u{00A0}" + (russian ? "кг" : "kg")
  }

  // MARK: Start

  private func startButton(_ program: WorkoutProgram, running: Bool) -> some View {
    Button {
      start(program.id)
    } label: {
      HStack(spacing: 8) {
        RitmSymbol("play.fill").font(.system(size: 18))
        Text(
          running
            ? store.text("Продолжить тренировку", "Resume workout")
            : store.text("Начать тренировку", "Start workout")
        )
        .ritmFont(16, weight: .bold, tracking: -0.01)
      }
      .foregroundStyle(Color.white)
      .frame(maxWidth: .infinity, minHeight: 56)
      .background {
        Capsule().fill(WorkoutPalette.gradient(program.colorIndex))
          .overlay { Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1) }
          .shadow(color: .black.opacity(0.45), radius: 10, y: 8)
      }
      .contentShape(Capsule())
    }
    .buttonStyle(RitmPressStyle(scale: 0.97))
    .padding(.horizontal, 16)
    .disabled(program.items.isEmpty)
  }
}
