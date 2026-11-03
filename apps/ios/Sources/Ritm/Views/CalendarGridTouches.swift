import RitmCore
import SwiftUI
import UIKit

/// Finger handling of the week grid, as UIKit recognisers on the grid's own scroll view.
///
/// SwiftUI drag gestures on a scroll view or its content (a zero-distance drag for the hold, a
/// drag for the week swipe) compete with the scroll view's pan and on iOS 27 left the hour grid
/// stuck. Recognisers added to the `UIScrollView` itself recognise together with its pan, so a
/// plain vertical swipe anywhere on the grid always scrolls:
/// - a long press (0.35 s, moving less than 10 pt before it fires) lifts the entry under the
///   finger; after that the finger drags it and the grid scrolling is switched off by the model;
/// - a horizontal-dominant pan moves the grid sideways and changes the week.
struct CalendarGridTouches: UIViewRepresentable {
  let model: WeekDragModel
  /// The drag environment for the current layout, built when a finger event arrives.
  let makeEnv: () -> WeekDragEnv
  let swipeLimit: CGFloat
  let onSwipeChange: (CGFloat) -> Void
  let onSwipeEnd: (_ dx: CGFloat, _ dy: CGFloat, _ elapsed: TimeInterval) -> Void

  func makeUIView(context: Context) -> HostView {
    let view = HostView()
    view.isUserInteractionEnabled = false
    view.coordinator = context.coordinator
    return view
  }

  func updateUIView(_ view: HostView, context: Context) {
    context.coordinator.parent = self
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  /// Sits in the scroll content only to find the scroll view that holds it.
  final class HostView: UIView {
    weak var coordinator: Coordinator?

    override func didMoveToWindow() {
      super.didMoveToWindow()
      guard window != nil else {
        coordinator?.detach()
        return
      }
      var candidate = superview
      while let current = candidate, !(current is UIScrollView) { candidate = current.superview }
      coordinator?.attach(to: candidate as? UIScrollView)
    }
  }

  @MainActor
  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var parent: CalendarGridTouches
    private weak var scrollView: UIScrollView?
    private let press = UILongPressGestureRecognizer()
    private let pan = UIPanGestureRecognizer()
    private var panStart = Date()

    init(_ parent: CalendarGridTouches) {
      self.parent = parent
      super.init()
      press.minimumPressDuration = CalendarPlan.dragHold
      press.allowableMovement = CGFloat(CalendarPlan.dragHoldSlop)
      press.cancelsTouchesInView = false
      press.delegate = self
      press.addTarget(self, action: #selector(pressed(_:)))
      pan.cancelsTouchesInView = false
      pan.delegate = self
      pan.addTarget(self, action: #selector(panned(_:)))
    }

    func attach(to scroll: UIScrollView?) {
      guard scrollView !== scroll else { return }
      detach()
      guard let scroll else { return }
      scroll.addGestureRecognizer(press)
      scroll.addGestureRecognizer(pan)
      scrollView = scroll
    }

    func detach() {
      press.view?.removeGestureRecognizer(press)
      pan.view?.removeGestureRecognizer(pan)
      scrollView = nil
    }

    // MARK: Hold and drag

    /// The finger in the visible part of the grid, and how far the grid is scrolled.
    private func finger(_ recogniser: UIGestureRecognizer, in scroll: UIScrollView)
      -> (point: CGPoint, offset: CGFloat)
    {
      let content = recogniser.location(in: scroll)
      let origin = scroll.bounds.origin
      return (CGPoint(x: content.x - origin.x, y: content.y - origin.y), origin.y)
    }

    @objc private func pressed(_ recogniser: UILongPressGestureRecognizer) {
      guard let scroll = scrollView else { return }
      let model = parent.model
      let (point, offset) = finger(recogniser, in: scroll)
      switch recogniser.state {
      case .began:
        model.offset = offset
        model.pressBegan(at: point, env: parent.makeEnv())
      case .changed:
        model.offset = offset
        model.pressMoved(to: point, env: parent.makeEnv())
      case .ended:
        model.offset = offset
        model.pressEnded(at: point, env: parent.makeEnv())
      case .cancelled, .failed:
        model.pressInterrupted()
      default:
        break
      }
    }

    // MARK: Week swipe

    @objc private func panned(_ recogniser: UIPanGestureRecognizer) {
      guard let scroll = scrollView else { return }
      let move = recogniser.translation(in: scroll)
      switch recogniser.state {
      case .began:
        panStart = Date()
        parent.onSwipeChange(clamped(move.x))
      case .changed:
        parent.onSwipeChange(clamped(move.x))
      case .ended:
        parent.onSwipeEnd(move.x, move.y, Date().timeIntervalSince(panStart))
      case .cancelled, .failed:
        parent.onSwipeEnd(0, 0, 0)
      default:
        break
      }
    }

    private func clamped(_ dx: CGFloat) -> CGFloat {
      max(-parent.swipeLimit, min(parent.swipeLimit, dx))
    }

    // MARK: Delegate

    /// The week swipe begins only for a clearly horizontal move and never while an entry is held.
    func gestureRecognizerShouldBegin(_ recogniser: UIGestureRecognizer) -> Bool {
      guard recogniser === pan else { return true }
      guard !parent.model.active, let scroll = scrollView else { return false }
      let move = pan.translation(in: scroll)
      return abs(move.x) > 8 && abs(move.x) > abs(move.y) * 1.2
    }

    func gestureRecognizer(
      _ recogniser: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }
}
