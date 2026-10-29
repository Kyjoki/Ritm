import RitmCore
import SwiftUI

// Motion tokens and helpers from board/proto/MOTION.md. Nothing appears from nowhere, nothing
// blocks input, and with Reduce Motion everything is instant or a plain 120 ms fade.

enum RitmMotion {
  // MARK: Curves

  /// `cubic-bezier(.22, 1, .36, 1)`, the easing of the first web transitions; kept for the
  /// call sites that already use it.
  static func ease(_ duration: Double) -> Animation {
    .timingCurve(0.22, 1, 0.36, 1, duration: duration)
  }
  /// `cubic-bezier(.2, .8, .2, 1)`: the default curve.
  static func easeOut(_ duration: Double) -> Animation {
    .timingCurve(0.2, 0.8, 0.2, 1, duration: duration)
  }
  /// `cubic-bezier(.65, 0, .35, 1)`: theme reveal and other symmetric moves.
  static func easeInOut(_ duration: Double) -> Animation {
    .timingCurve(0.65, 0, 0.35, 1, duration: duration)
  }
  /// `cubic-bezier(.34, 1.32, .5, 1)`: popovers and panels inflating from their trigger
  /// (overshoot of at most 4 %).
  static func inflate(_ duration: Double = RitmMotion.inflateOpen) -> Animation {
    .timingCurve(0.34, 1.32, 0.5, 1, duration: duration)
  }
  /// Closing back into the trigger: plain ease-out, no overshoot.
  static var inflateClose: Animation { easeOut(inflateCloseDuration) }
  /// Ease-out cubic, the curve of the count-up numbers.
  static func easeOutCubic(_ duration: Double) -> Animation {
    .timingCurve(0.215, 0.61, 0.355, 1, duration: duration)
  }
  /// The 120 ms fade that replaces every movement under Reduce Motion.
  static var reducedFade: Animation { .easeOut(duration: 0.12) }

  // MARK: Durations (seconds)

  static let pageEnter = 0.38
  static let pageExit = 0.12
  static let inflateOpen = 0.3
  static let inflateCloseDuration = 0.18
  static let countFirst = CountInterpolation.firstDuration
  static let countChange = CountInterpolation.changeDuration
  static let chartDraw = 0.78
  static let ringSweep = 0.7
  static let barGrow = 0.5
  static let barStagger = 0.04
  static let sheet = 0.34
  static let sheetClose = 0.24
  static let backdrop = 0.22
  static let themeReveal = 0.52

  // MARK: Page reveal geometry

  /// Children of a page rise this far while they fade in.
  static let revealOffset: CGFloat = 14

  // MARK: Press

  static let pressScale: CGFloat = 0.97
  static var press: Animation { easeOut(0.13) }

  // MARK: Existing short transitions

  static var indicator: Animation { ease(0.24) }
  static var dialogIn: Animation { ease(0.24) }
  static var dialogOut: Animation { .easeIn(duration: 0.18) }

  // MARK: Charts (MOTION.md §4)

  /// The stroke of a line chart draws from 0 to 100 %.
  static var lineDraw: Animation { easeOut(chartDraw) }
  /// The area under the line fades in over 300 ms once the line has passed 40 %.
  static var areaFade: Animation { easeOut(0.3).delay(chartDraw * 0.4) }
  /// The end point pops in (scale .6 to 1, 160 ms) when the line arrives.
  static var dotPop: Animation { easeOut(0.16).delay(chartDraw) }
  /// A bar grows from the baseline, 40 ms after the previous one.
  static func barGrow(index: Int) -> Animation {
    easeOut(barGrow).delay(Double(max(0, index)) * barStagger)
  }
  /// A donut, ring or gauge sweeps from 0 to its value.
  static var sweep: Animation { easeOut(ringSweep) }
  /// Legend rows fade in one after another while the ring sweeps.
  static func legendFade(index: Int) -> Animation {
    easeOut(0.3).delay(0.2 + Double(max(0, index)) * 0.045)
  }
}

// MARK: - Page visit

private struct RitmPageVisit: ViewModifier {
  let enter: () -> Void
  let leave: () -> Void
  @Environment(\.ritmPageActive) private var active

  func body(content: Content) -> some View {
    content
      .onAppear { if active { enter() } }
      .onChange(of: active) { _, isActive in
        if isActive { enter() } else { leave() }
      }
  }
}

extension View {
  /// Calls `enter` when the view appears on the visible page and each time the page is shown
  /// again, `leave` when the page is left. Pages stay alive in the root view, so this is what
  /// makes a return visit replay its motion. Re-rendering with new data calls neither.
  func ritmPageVisit(enter: @escaping () -> Void, leave: @escaping () -> Void) -> some View {
    modifier(RitmPageVisit(enter: enter, leave: leave))
  }
}

// MARK: - Page reveal

private struct RitmPageReveal: ViewModifier {
  let index: Int
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shown = false

  func body(content: Content) -> some View {
    content
      .opacity(shown ? 1 : 0)
      .offset(y: shown || reduceMotion ? 0 : RitmMotion.revealOffset)
      .ritmPageVisit(enter: reveal, leave: { shown = false })
  }

  private func reveal() {
    guard !shown else { return }
    let animation =
      reduceMotion
      ? RitmMotion.reducedFade
      : RitmMotion.easeOut(RitmMotion.pageEnter).delay(MotionStagger.delay(index: index))
    withAnimation(animation) { shown = true }
  }
}

extension View {
  /// MOTION.md §2: the view starts at opacity 0, 14 pt lower, and settles over 380 ms; the
  /// first eight children of a page are staggered by 45 ms. It runs once per page visit and
  /// never because the page re-rendered.
  func ritmPageReveal(index: Int) -> some View {
    modifier(RitmPageReveal(index: index))
  }
}

// MARK: - Press

extension View {
  /// Press feedback for custom controls: scale .97 over 130 ms (a slight dimming under
  /// Reduce Motion). Buttons should normally use `RitmPressStyle`, which does the same.
  func ritmPressEffect(_ pressed: Bool, reduceMotion: Bool) -> some View {
    scaleEffect(pressed && !reduceMotion ? RitmMotion.pressScale : 1)
      .opacity(pressed && reduceMotion ? 0.8 : 1)
      .animation(reduceMotion ? nil : RitmMotion.press, value: pressed)
  }
}

// MARK: - Chart draw-in

/// Hands a chart a flag that is false until its page is visible and true afterwards, so the
/// chart animates from the empty state with `.animation(_, value: drawn)`. `key` identifies the
/// data set: the draw replays when the key changes or the page is visited again, and never
/// because an unrelated value (a ticked checkbox) re-rendered the page. With Reduce Motion the
/// flag is always true.
struct RitmDrawGate<Key: Hashable, Content: View>: View {
  let key: Key
  private let content: (Bool) -> Content

  init(key: Key, @ViewBuilder content: @escaping (_ drawn: Bool) -> Content) {
    self.key = key
    self.content = content
  }

  var body: some View {
    RitmDrawGateBody(content: content).id(key)
  }
}

private struct RitmDrawGateBody<Content: View>: View {
  let content: (Bool) -> Content
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var drawn = false

  var body: some View {
    content(drawn || reduceMotion)
      .ritmPageVisit(enter: { drawn = true }, leave: { drawn = false })
  }
}

// MARK: - Counting numbers

private struct RitmCountRun {
  var from: Double
  var to: Double
  /// nil while idle (not yet started, or settled on `from`).
  var begin: Date?
  var duration: Double

  static func idle(_ value: Double) -> RitmCountRun {
    RitmCountRun(from: value, to: value, begin: nil, duration: 0)
  }

  func value(at date: Date) -> Double {
    guard let begin, duration > 0 else { return from }
    return CountInterpolation.value(
      from: from, to: to, progress: date.timeIntervalSince(begin) / duration)
  }
}

/// A `Text` whose number really counts (MOTION.md §3): from 35 % of the final value on first
/// appearance, or from the value it showed before when the value changes, to the final one in
/// 600 ms / 450 ms with an ease-out cubic. `format` turns the running value into the final
/// string, so money, percentages and counters read exactly like the static text once settled.
/// It does not replay when the value stays the same, and under Reduce Motion it just shows the
/// final text.
struct RitmCountText: View {
  let value: Double
  let format: (Double) -> String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.ritmPageActive) private var active
  @State private var run: RitmCountRun

  init(_ value: Double, format: @escaping (Double) -> String) {
    self.value = value
    self.format = format
    _run = State(
      initialValue: .idle(CountInterpolation.start(final: value, previous: nil)))
  }

  /// An integer counter such as «3 из 5»: `format` receives the rounded running value.
  init(_ value: Int, format: @escaping (Int) -> String) {
    self.init(Double(value)) { format(Int($0.rounded())) }
  }

  var body: some View {
    Group {
      if reduceMotion {
        Text(format(value))
      } else {
        TimelineView(.animation(paused: run.begin == nil)) { context in
          Text(format(run.value(at: context.date)))
        }
      }
    }
    .monospacedDigit()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(format(value))
    .ritmPageVisit(enter: appear, leave: { run = .idle(firstStart) })
    .onChange(of: value) { _, newValue in change(to: newValue) }
  }

  private var firstStart: Double { CountInterpolation.start(final: value, previous: nil) }

  private func appear() {
    play(from: firstStart, to: value, isFirst: true)
  }

  private func change(to newValue: Double) {
    // A page that is not on screen counts when it is shown again, not now.
    guard active else {
      run = .idle(CountInterpolation.start(final: newValue, previous: nil))
      return
    }
    play(from: run.value(at: Date()), to: newValue, isFirst: false)
  }

  private func play(from: Double, to: Double, isFirst: Bool) {
    guard CountInterpolation.shouldAnimate(from: from, to: to) else {
      run = .idle(to)
      return
    }
    let duration = CountInterpolation.duration(isFirst: isFirst)
    let begin = Date()
    run = RitmCountRun(from: from, to: to, begin: begin, duration: duration)
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(duration + 0.05))
      // A newer run replaced this one; leave it alone.
      guard run.begin == begin else { return }
      run = .idle(to)
    }
  }
}
