import RitmCore
import SwiftUI

// The blocks of the «Тренировки» home: the week card, the program cards and the record cards.

// MARK: - Week card

/// `.a1-hero`: the ring «N/M на неделе», the week's volume against last week, the streak, and the
/// seven-day strip. A flat card with a soft accent glow in the corner.
struct WorkoutHeroCard: View {
  @Environment(RitmStore.self) private var store
  let week: WorkoutWeek
  let volume: Double
  let percent: Int?
  let streak: Int

  private var russian: Bool { store.language == .ru }
  private var dayNames: [String] {
    russian
      ? ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"] : ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    VStack(spacing: 0) {
      HStack(spacing: 14) {
        ring
        stats
      }
      strip.padding(.top, 12)
    }
    .padding(14)
    .background {
      ZStack(alignment: .topTrailing) {
        RitmPanelBackground(radius: 22)
        Circle()
          .fill(
            RadialGradient(
              colors: [RitmTheme.accentColor.opacity(0.2), .clear], center: .center, startRadius: 0,
              endRadius: 100)
          )
          .frame(width: 200, height: 200)
          .offset(x: 50, y: -70)
          .allowsHitTesting(false)
      }
      .clipShape(shape)
    }
    .accessibilityElement(children: .contain)
  }

  private var ring: some View {
    ZStack {
      WorkoutRing(progress: week.progress, lineWidth: 7.8)
      VStack(spacing: 1) {
        Text(week.goal > 0 ? "\(week.done)/\(week.goal)" : "—").ritmFont(21, weight: .bold, tracking: -0.05)
          .foregroundStyle(RitmTheme.text)
        Text(store.text("на неделе", "this week")).ritmFont(10).foregroundStyle(RitmTheme.muted)
      }
    }
    .frame(width: 78, height: 78)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      store.text(
        "\(week.done) из \(week.goal) на неделе", "\(week.done) of \(week.goal) this week"))
  }

  private var stats: some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text(store.text("Объём за неделю", "Volume this week"))
          .ritmFont(11.5).foregroundStyle(RitmTheme.muted).lineLimit(2)
        Text(WorkoutNumbers.volume(volume, russian: russian))
          .ritmFont(17, weight: .bold, tracking: -0.03).foregroundStyle(RitmTheme.text)
        if let percent, percent != 0 {
          Text((percent > 0 ? "▲ " : "▼ ") + "\(abs(percent))%")
            .ritmFont(11.5, weight: .bold)
            .foregroundStyle(percent > 0 ? WorkoutColors.income : RitmTheme.danger)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .leading, spacing: 1) {
        Text(store.text("Серия", "Streak")).ritmFont(11.5).foregroundStyle(RitmTheme.muted)
        HStack(spacing: 6) {
          RitmSymbol("flame").font(.system(size: 18)).foregroundStyle(WorkoutPalette.flame)
          Text(store.text("\(streak) нед.", "\(streak) wk"))
            .ritmFont(17, weight: .bold, tracking: -0.03).foregroundStyle(RitmTheme.text)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
  }

  private var strip: some View {
    HStack(alignment: .bottom, spacing: 6) {
      ForEach(week.days, id: \.key) { day in
        VStack(spacing: 5) {
          Spacer(minLength: 0)
          bar(day)
          Text(dayNames[day.index])
            .ritmFont(10.5, weight: day.isToday ? .bold : .medium)
            .foregroundStyle(day.isToday ? RitmTheme.accentColor : RitmTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          dayNames[day.index] + ", "
            + (day.isDone ? store.text("выполнено", "done") : store.text("не выполнено", "not done")))
      }
    }
    .frame(height: 50)
    .padding(.top, 12)
    .overlay(alignment: .top) { Rectangle().fill(RitmTheme.line).frame(height: 1) }
  }

  @ViewBuilder private func bar(_ day: WorkoutWeekDay) -> some View {
    let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
    let height: CGFloat = day.isDone ? 30 : (day.isToday ? 20 : 6)
    Group {
      if day.isDone {
        shape.fill(RitmTheme.accentColor)
          .overlay {
            if day.isToday {
              shape.inset(by: -3.5).strokeBorder(RitmTheme.accentColor, lineWidth: 1.5)
            }
          }
      } else if day.isToday {
        shape.strokeBorder(RitmTheme.accentColor, lineWidth: 1.5)
      } else {
        shape.fill(RitmTheme.ringTrack)
      }
    }
    .frame(maxWidth: 28)
    .frame(height: height)
  }
}

// MARK: - Programs

/// `.hs`: the program cards in a row, ending with «Новая программа».
struct WorkoutProgramsRow: View {
  @Environment(RitmStore.self) private var store
  let programs: [WorkoutProgram]
  let russian: Bool
  let open: (String) -> Void
  let start: (String) -> Void
  let add: () -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      LazyHStack(spacing: 10) {
        ForEach(programs) { program in
          WorkoutProgramCard(
            program: program, russian: russian, open: { open(program.id) }, start: { start(program.id) })
        }
        WorkoutDashedAdd(
          title: store.text("Новая программа", "New program"), width: 90, height: 120, radius: 20,
          action: add)
      }
      .padding(.horizontal, 16).padding(.vertical, 12)
    }
    .padding(.horizontal, -16).padding(.vertical, -12)
  }
}

/// `.a2-pc`: a gradient card, 142 × 120: letter tile, ▶ start, name, «N упр. · ≈M мин».
private struct WorkoutProgramCard: View {
  @Environment(RitmStore.self) private var store
  let program: WorkoutProgram
  let russian: Bool
  let open: () -> Void
  let start: () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Button(action: open) {
        VStack(alignment: .leading, spacing: 0) {
          Text(String(program.name.first(where: { $0.isLetter || $0.isNumber }) ?? "•").uppercased())
            .ritmFont(16, weight: .bold)
            .frame(width: 34, height: 34)
            .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
          Spacer(minLength: 4)
          Text(program.name.isEmpty ? store.text("Без названия", "Untitled") : program.name)
            .ritmFont(14.5, weight: .bold, tracking: -0.03).lineLimit(2)
            .multilineTextAlignment(.leading)
          Text(
            russian
              ? "\(program.items.count) упр. · ≈\(program.estimatedMinutes) мин"
              : "\(program.items.count) ex. · ≈\(program.estimatedMinutes) min"
          )
          .ritmFont(11).opacity(0.85).lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(12)
        .frame(width: 142, height: 120, alignment: .leading)
        .background { WorkoutGradientSurface(colorIndex: program.colorIndex, radius: 20) }
        .contentShape(Rectangle())
      }
      .buttonStyle(RitmPressStyle())
      .accessibilityLabel(program.name)
      Button(action: start) {
        RitmSymbol("play.fill").font(.system(size: 14))
          .foregroundStyle(Color(rgb: 0x4A2A8F))
          .frame(width: 34, height: 34)
          .background(Color.white, in: Circle())
          .frame(width: 44, height: 44)
          .contentShape(Circle())
      }
      .buttonStyle(RitmPressStyle(scale: 0.92))
      .padding(.top, 7).padding(.trailing, 7)
      .accessibilityLabel(store.text("Начать тренировку «\(program.name)»", "Start workout “\(program.name)”"))
    }
  }
}

/// `.a2-add`, `.rc-add`: a dashed «+» tile at the end of a row.
struct WorkoutDashedAdd: View {
  let title: String
  let width: CGFloat
  let height: CGFloat
  let radius: CGFloat
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        RitmSymbol("plus").font(.system(size: 22))
        Text(title).ritmFont(12, weight: .semibold).multilineTextAlignment(.center)
      }
      .foregroundStyle(RitmTheme.accentColor)
      .frame(width: width, height: height)
      .overlay {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .strokeBorder(RitmTheme.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
  }
}

// MARK: - Records

/// `.rec-row`: the record cards, ending with «Рекорд».
struct WorkoutRecordsRow: View {
  @Environment(RitmStore.self) private var store
  let cards: [WorkoutRecordCard]
  let edit: (WorkoutRecordCard) -> Void
  let add: () -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      LazyHStack(spacing: 10) {
        ForEach(cards) { card in
          WorkoutRecordCardView(card: card) { edit(card) }
        }
        WorkoutDashedAdd(
          title: store.text("Рекорд", "Record"), width: 84, height: 92, radius: 16, action: add)
      }
      .padding(.horizontal, 16).padding(.vertical, 12)
    }
    .padding(.horizontal, -16).padding(.vertical, -12)
  }
}

private struct WorkoutRecordCardView: View {
  @Environment(RitmStore.self) private var store
  let card: WorkoutRecordCard
  let action: () -> Void

  var body: some View {
    let russian = store.language == .ru
    Button(action: action) {
      VStack(alignment: .leading, spacing: 0) {
        Text(card.name).ritmFont(11).foregroundStyle(RitmTheme.muted)
          .lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading)
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text(WorkoutFormat.weight(card.weight, comma: russian))
            .ritmFont(20, weight: .bold, tracking: -0.04).foregroundStyle(RitmTheme.text)
          Text(russian ? "кг" : "kg").ritmFont(11).foregroundStyle(RitmTheme.muted)
        }
        .padding(.top, 3)
        Text("★ " + WorkoutText.shortDate(card.date, language: store.language))
          .ritmFont(10.5).foregroundStyle(WorkoutPalette.gold)
      }
      .padding(.horizontal, 12).padding(.vertical, 10)
      .frame(width: 118, height: 92, alignment: .topLeading)
      .background { RitmPanelBackground(radius: 16) }
      .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
    .accessibilityLabel(
      "\(card.name), \(WorkoutFormat.weight(card.weight, comma: russian)) " + (russian ? "кг" : "kg"))
  }
}
