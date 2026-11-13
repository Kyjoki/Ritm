import RitmCore
import SwiftUI

/// One period of the hour grid (a day, three days or a week): the hour lines and the day columns,
/// the whole width of the day area. Equatable on what it shows: its days, their stamps and the
/// sizes. The closures and the placed entries are not compared, so a page that is only moving or
/// whose neighbours changed is never built again.
struct CalendarHourPage: View, Equatable {
  let days: [String]
  let stamps: [Int]
  let placed: [[PlacedOccurrence]]
  let column: CGFloat
  let height: CGFloat
  let today: String
  let liftedKey: String?
  let hint: (DayOccurrence) -> String
  let onOpen: (DayOccurrence) -> Void
  let onTap: (String, CGPoint) -> Void
  let onAddMorning: (String) -> Void

  private let hour = CGFloat(CalendarPlan.hourHeight)

  nonisolated static func == (left: CalendarHourPage, right: CalendarHourPage) -> Bool {
    left.days == right.days && left.stamps == right.stamps && left.column == right.column
      && left.height == right.height && left.today == right.today
      && left.liftedKey == right.liftedKey
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      CalendarGridLines(hour: hour, column: column, columns: days.count, vertical: false)
        .stroke(RitmTheme.line, lineWidth: 1)
      CalendarGridLines(hour: hour, column: column, columns: days.count, vertical: true)
        .stroke(RitmTheme.line.opacity(0.75), lineWidth: 1)
      HStack(spacing: 0) {
        ForEach(Array(days.enumerated()), id: \.element) { index, day in
          CalendarDayColumn(
            day: day, placed: placed[index], column: column, height: height, isToday: day == today,
            liftedKey: liftedKey, stamp: stamps[index], hint: hint, onOpen: onOpen,
            onTap: { point in onTap(day, point) }, onAddMorning: { onAddMorning(day) }
          )
          .equatable()
        }
      }
    }
    .frame(width: column * CGFloat(days.count), height: height, alignment: .topLeading)
  }
}
