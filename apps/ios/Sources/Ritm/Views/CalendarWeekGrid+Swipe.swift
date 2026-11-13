import RitmCore
import SwiftUI

// The swipe between periods of the hour grid: the finger and the slide only write the pager's
// position; the period is committed once, when the slide has finished.

extension CalendarWeekGrid {
  /// A slide of one page.
  private static let slideDuration = 0.28
  /// The slide ends by itself; this is only the net under it, in case the completion is lost.
  private static let slideWatchdog = Duration.milliseconds(700)
  /// How long the page must be left alone before the neighbour ahead is built.
  private static let quiet = Duration.milliseconds(150)

  /// The finger moves the strips with it, one page either way at most.
  func dragSwipe(_ dx: CGFloat, width: CGFloat) {
    guard !pager.sliding, !model.active else { return }
    if !pager.dragging {
      pager.dragging = true
      pager.moving = true
      warmNow()
    }
    pager.value = Double(shown.slot) + max(-1, min(1, Double(-dx / max(1, width))))
  }

  /// A deliberate horizontal swipe slides to the next or previous period; anything else settles
  /// the pages back.
  func finishSwipe(dx: CGFloat, dy: CGFloat, elapsed: TimeInterval, width: CGFloat) {
    pager.dragging = false
    let direction = model.active ? 0 : CalendarPlan.weekSwipe(dx: dx, dy: dy, elapsed: elapsed, width: width)
    guard direction != 0 else {
      settle()
      return
    }
    advance(direction)
  }

  func settle() {
    pager.dragging = false
    guard !pager.sliding else { return }
    pager.moving = false
    withAnimation(reduceMotion ? nil : RitmMotion.easeOut(0.22)) { pager.value = Double(shown.slot) }
  }

  /// Slides one period forward (1) or back (-1) over pages that are already built, then commits.
  func advance(_ direction: Int) {
    guard direction != 0, !pager.sliding else { return }
    let step = direction > 0 ? 1 : -1
    var start = shown
    if start.needsWarmUp(direction: step) {
      start.warmUp()
      window = start
    }
    pager.sliding = true
    pager.moving = true
    pager.dragging = false
    pager.token += 1
    let token = pager.token
    let target = Double(start.slot + step)
    guard !reduceMotion else {
      pager.value = target
      finishSlide(step, token: token)
      return
    }
    withAnimation(RitmMotion.easeOut(Self.slideDuration), completionCriteria: .logicallyComplete) {
      pager.value = target
    } completion: {
      finishSlide(step, token: token)
    }
    Task { @MainActor in
      try? await Task.sleep(for: Self.slideWatchdog)
      finishSlide(step, token: token)
    }
  }

  /// One state write for the window and one for the page's day: the pages do not move.
  private func finishSlide(_ step: Int, token: Int) {
    guard pager.sliding, pager.token == token else { return }
    pager.sliding = false
    pager.moving = false
    var next = shown
    next.commit(direction: step)
    window = next
    pager.restSlot = next.slot
    onStep(step)
  }

  /// Builds the neighbours now, for a finger that arrives before they were built.
  private func warmNow() {
    var next = shown
    guard !next.warm else { return }
    next.warmUp()
    window = next
  }

  /// Once the page is quiet: the neighbours are read in the background, built, and the next ring
  /// of days is read ahead for the following swipe.
  func buildNeighbours() async {
    let base = shown
    await dayModel.prewarm(base.days(slot: base.slot - 1) + base.days(slot: base.slot + 1))
    try? await Task.sleep(for: Self.quiet)
    guard !Task.isCancelled, !pager.moving else { return }
    var next = shown
    if !next.warm {
      next.warmUp()
      window = next
    }
    await dayModel.prewarm(next.daysToPrepare())
  }
}
