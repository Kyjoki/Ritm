import RitmCore
import SwiftUI

/// One day's column of the hour grid: the blocks, the current-time line and the tap that adds an
/// entry. Equatable: while the grid slides sideways or its overlays open, an unchanged column is
/// not built again. A tap is decided by position in the grid (`onTap`), never by the blocks, so
/// a tap on a block and a tap on empty space can never both fire.
struct CalendarDayColumn: View, Equatable {
  let day: String
  let placed: [PlacedOccurrence]
  let column: CGFloat
  let height: CGFloat
  let isToday: Bool
  let liftedKey: String?
  let generation: Int
  let hint: (DayOccurrence) -> String
  let onOpen: (DayOccurrence) -> Void
  let onTap: (CGPoint) -> Void
  let onAddMorning: () -> Void
  @Environment(RitmStore.self) private var store

  private let hour = CGFloat(CalendarPlan.hourHeight)

  nonisolated static func == (left: CalendarDayColumn, right: CalendarDayColumn) -> Bool {
    left.day == right.day && left.generation == right.generation && left.column == right.column
      && left.height == right.height && left.isToday == right.isToday
      && left.liftedKey == right.liftedKey
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      (isToday ? RitmTheme.soft.opacity(0.34) : Color.clear)
      ForEach(placed) { item in
        CalendarGridEvent(
          placed: item, column: column, hour: hour, lifted: liftedKey == item.entry.key,
          hint: hint(item.entry), onOpen: { onOpen(item.entry) })
      }
      if isToday { nowLine }
    }
    .frame(width: column, height: height, alignment: .topLeading)
    .contentShape(Rectangle())
    .gesture(SpatialTapGesture().onEnded { value in onTap(value.location) })
    .accessibilityElement(children: .contain)
    .accessibilityLabel(
      FeatureDate.label(day, zone: store.timeZone, language: store.language, template: "EEEE d MMMM")
    )
    .accessibilityAction(named: store.text("Добавить запись в 9 AM", "Add an entry at 9 AM")) {
      onAddMorning()
    }
  }

  private var nowLine: some View {
    TimelineView(.everyMinute) { context in
      let minute = FeatureDate.calendar(store.timeZone).dateComponents([.hour, .minute], from: context.date)
      CalendarNowLine()
        .offset(y: CGFloat((minute.hour ?? 0) * 60 + (minute.minute ?? 0)) / 60 * hour - 1)
    }
    .allowsHitTesting(false)
  }
}

/// `.cal-now-line`: a 2 pt line with a dot at its start.
struct CalendarNowLine: View {
  var body: some View {
    Rectangle()
      .fill(RitmTheme.danger)
      .frame(height: 2)
      .overlay(alignment: .leading) {
        Circle().fill(RitmTheme.danger).frame(width: 10, height: 10).offset(x: -5)
      }
      .accessibilityHidden(true)
  }
}

/// Whole-hour lines across the columns, or the separators between them. They run the full height
/// of the scroll content, the empty tail under midnight included.
struct CalendarGridLines: Shape {
  let hour: CGFloat
  let column: CGFloat
  let columns: Int
  let vertical: Bool

  func path(in rect: CGRect) -> Path {
    var path = Path()
    if vertical {
      for index in 0..<max(1, columns) {
        let x = CGFloat(index) * column + 0.5
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: rect.height))
      }
    } else {
      var y = hour + 0.5
      while y < rect.height {
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: rect.width, y: y))
        y += hour
      }
    }
    return path
  }
}
