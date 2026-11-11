import RitmCore
import SwiftUI

/// The block of one entry in the hour grid: a solid, saturated colour, the title wrapped over as
/// many lines as fit and the time under it when the block is tall enough. It has no position and
/// no gestures, so the lifted copy under the finger looks the same.
struct CalendarEventCard: View {
  let entry: DayOccurrence
  let width: CGFloat
  let height: CGFloat
  @Environment(RitmStore.self) private var store
  @Environment(\.calendarHourFormat) private var format
  @ScaledMetric(relativeTo: .caption) private var lineHeight: CGFloat = 14

  private static let radius: CGFloat = 7
  private static let padding: CGFloat = 3
  /// Below this height the block is a single title line; the time would not fit.
  private static let timeMinHeight: CGFloat = 38
  /// A block narrower than this shows only the start time.
  private static let wideBlock: CGFloat = 96

  private var showsTime: Bool { height >= Self.timeMinHeight && entry.start != nil }

  private var titleLines: Int {
    let room = height - Self.padding * 2 - (showsTime ? lineHeight : 0)
    return max(1, Int(room / lineHeight))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(CalendarText.marker(entry) + entry.title)
        .ritmFont(11, weight: .semibold)
        .lineLimit(titleLines)
        .multilineTextAlignment(.leading)
        .strikethrough(entry.completed)
      if showsTime {
        Text(time)
          .ritmFont(11)
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
    }
    .foregroundStyle(CalendarPalette.ink(entry.colorId))
    .padding(.vertical, Self.padding)
    .padding(.leading, 5)
    .padding(.trailing, 3)
    .frame(width: width, height: height, alignment: .topLeading)
    .background {
      let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
      shape.fill(CalendarPalette.solid(entry.colorId))
        .overlay { shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
    }
    .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
    .opacity(entry.completed ? 0.6 : 1)
  }

  private var time: String {
    let base =
      width >= Self.wideBlock
      ? format.entryRange(entry) : format.entryTime(entry, start: true)
    return base + (entry.clockChange && width >= Self.wideBlock ? store.text(" · Перевод часов", " · Clock change") : "")
  }
}

/// `.cal-grid-event`: a tap opens the entry; the hold that lifts it is handled by the grid, which
/// also dims this card while its copy is in the air.
struct CalendarGridEvent: View {
  let placed: PlacedOccurrence
  let column: CGFloat
  let hour: CGFloat
  let lifted: Bool
  let hint: String
  let onOpen: () -> Void
  @Environment(RitmStore.self) private var store

  var body: some View {
    let frame = CalendarPlan.entryFrame(placed, column: Double(column), hourHeight: Double(hour))
    CalendarEventCard(
      entry: placed.entry, width: CGFloat(frame.width), height: CGFloat(frame.height)
    )
    .opacity(lifted ? 0.3 : 1)
    .offset(x: CGFloat(frame.x), y: CGFloat(frame.y))
    .zIndex(1)
    // Touches are resolved by position in the column (the grid), never by this card.
    .allowsHitTesting(false)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(CalendarText.occurrenceLabel(placed.entry, store: store))
    .accessibilityHint(hint)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction(.default, onOpen)
  }
}

/// An all-day or untimed entry as a chip in the row above the hours, and the same chip in a
/// month cell: a solid bar with a single line of text.
struct CalendarChip: View {
  let entry: DayOccurrence
  var fontSize: CGFloat = 11
  var height: CGFloat = 20

  var body: some View {
    Text(CalendarText.marker(entry) + entry.title)
      .ritmFont(fontSize, weight: .semibold)
      .lineLimit(1)
      .strikethrough(entry.completed)
      .foregroundStyle(CalendarPalette.ink(entry.colorId))
      .padding(.horizontal, 4)
      .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
      .background(
        CalendarPalette.solid(entry.colorId), in: RoundedRectangle(cornerRadius: 5, style: .continuous)
      )
      .opacity(entry.completed ? 0.6 : 1)
  }
}
