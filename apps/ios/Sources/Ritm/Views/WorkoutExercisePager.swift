import RitmCore
import SwiftUI

/// The position of a card among the exercises, read by `WorkoutPagerLayout`.
private struct WorkoutPageIndex: LayoutValueKey {
  static let defaultValue = 0
}

/// Cards side by side, `gap` apart, with the one at `position` in the frame. `position` is
/// animatable: moving between exercises animates it, so the cards that are already built slide
/// past each other and nothing is built or torn down while it runs. The height follows the
/// cards, so the buttons under the page glide to their new place together with the slide.
private struct WorkoutPagerLayout: Layout {
  var position: Double
  var gap: CGFloat = 24

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
    let pitch = bounds.width + gap
    for subview in subviews {
      let x = bounds.minX + CGFloat(Double(subview[WorkoutPageIndex.self]) - position) * pitch
      subview.place(
        at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
        proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
  }

  /// Between the heights of the two cards the position is between.
  private func height(width: CGFloat, subviews: Subviews) -> CGFloat {
    var heights: [Int: CGFloat] = [:]
    for subview in subviews {
      heights[subview[WorkoutPageIndex.self]] =
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

/// The exercise cards of the running workout as a pager. The current card and its neighbours stay
/// built (see `WorkoutPagerWindow`), so a swipe or the arrows only animate the position of cards
/// that already exist: no `.id` swap, no table built while the page moves, no group opacity over a
/// table. A far jump or Reduce Motion cross-fades instead of sliding.
struct WorkoutExercisePager<Page: View>: View {
  let items: [WorkoutSessionItem]
  let window: WorkoutPagerWindow
  let page: (WorkoutSessionItem) -> Page

  private struct Slot: Identifiable {
    let index: Int
    let item: WorkoutSessionItem
    var id: String { item.id }
  }

  var body: some View {
    let current = min(window.current, max(0, items.count - 1))
    let slots = window.indices(count: items.count).map { Slot(index: $0, item: items[$0]) }
    let transition: AnyTransition =
      window.fade ? .opacity.animation(RitmMotion.easeOut(0.22)) : .identity
    WorkoutPagerLayout(position: Double(current)) {
      ForEach(slots) { slot in
        page(slot.item)
          .allowsHitTesting(slot.index == current)
          .accessibilityHidden(slot.index != current)
          .transition(transition)
          .layoutValue(key: WorkoutPageIndex.self, value: slot.index)
      }
    }
  }
}
