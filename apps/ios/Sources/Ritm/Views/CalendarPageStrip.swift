import RitmCore
import SwiftUI

/// Where the strip of pages is: the slot of the page on the screen, as a fractional number while
/// a finger drags or a slide runs. Only the strips read `value`, so a drag or a slide re-evaluates
/// them and nothing else; the page behind them is not redrawn for it.
@MainActor @Observable
final class CalendarPagerPosition {
  var value = 0.0
  /// A finger is on the grid or a slide is running: the page's data must not be swapped now.
  @ObservationIgnored var moving = false
  /// A finger is dragging the pages.
  @ObservationIgnored var dragging = false
  /// A slide to the next or previous period is running; `token` tells slides apart.
  @ObservationIgnored var sliding = false
  @ObservationIgnored var token = 0
  /// The slot the pages rest on between moves, so a grid created later starts there.
  @ObservationIgnored var restSlot = 0
}

/// The slot of a page, read by `CalendarPagerLayout`.
private struct CalendarPageSlot: LayoutValueKey {
  static let defaultValue = 0
}

/// Pages side by side, one width apart, with the page at `position` in the frame. `position` is
/// animatable: the pages are already built, so a slide only changes where they are placed. The
/// height follows the pages (the day rows above the hours differ from week to week), so what is
/// below the strip glides to its new place together with the slide.
private struct CalendarPagerLayout: Layout {
  var position: Double

  var animatableData: Double {
    get { position }
    set { position = newValue }
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? subviews.first?.sizeThatFits(.unspecified).width ?? 0
    return CGSize(width: width, height: height(width: width, subviews: subviews))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    for subview in subviews {
      let x = bounds.minX + CGFloat(Double(subview[CalendarPageSlot.self]) - position) * bounds.width
      subview.place(
        at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
        proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
  }

  /// Between the heights of the two pages the position is between.
  private func height(width: CGFloat, subviews: Subviews) -> CGFloat {
    var heights: [Int: CGFloat] = [:]
    for subview in subviews {
      heights[subview[CalendarPageSlot.self]] =
        subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
    }
    let lower = Int(position.rounded(.down))
    let progress = CGFloat(position - Double(lower))
    switch (heights[lower], heights[lower + 1]) {
    case let (from?, to?): return from + (to - from) * progress
    case let (from?, nil): return from
    case let (nil, to?): return to
    case (nil, nil): return heights.values.max() ?? 0
    }
  }
}

/// The pages of a window in a row. `page` builds the page of a slot; it is called again for
/// every frame of a drag, so it must only create equatable views (cheap to compare, skipped when
/// nothing changed).
struct CalendarPageStrip<Page: View>: View {
  let position: CalendarPagerPosition
  let window: CalendarPagerWindow
  let page: (Int) -> Page

  var body: some View {
    CalendarPagerLayout(position: position.value) {
      ForEach(window.slots, id: \.self) { slot in
        page(slot)
          .allowsHitTesting(slot == window.slot)
          .accessibilityHidden(slot != window.slot)
          .layoutValue(key: CalendarPageSlot.self, value: slot)
      }
    }
  }
}
