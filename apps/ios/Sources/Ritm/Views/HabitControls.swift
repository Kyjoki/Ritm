import RitmCore
import SwiftUI

// Small controls of the habits page: `.sh-ib` (44 pt round icon button), `.sh-btn` / `.sh-sec`
// (44 pt capsules) and a cached date-label helper. They are flat fills with a specular rim, not
// a glass layer each: a card holds up to eight of them.

/// `.sh-ib`: a 44 pt circle with a muted icon on a raised fill.
struct HabitIconButton: View {
  let symbol: String
  let label: String
  let action: () -> Void
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button(action: action) {
      RitmSymbol(symbol)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(RitmTheme.muted)
        .frame(width: 44, height: 44)
        .background { Circle().fill(RitmTheme.glassRaised) }
        .overlay { Circle().strokeBorder(RitmGlassTokens.rim, lineWidth: RitmGlassTokens.rimWidth) }
        .contentShape(Circle())
        .opacity(isEnabled ? 1 : 0.45)
    }
    .buttonStyle(RitmPressStyle(scale: RitmGlassTokens.pressScale))
    .accessibilityLabel(label)
  }
}

/// `.sh-btn` (12.5 pt) and `.sh-sec` (11 pt): a capsule at least 44 pt tall; `prominent` is the
/// accent call to action (`.sh-btn.pri`).
struct HabitCapsuleStyle: ButtonStyle {
  var prominent = false
  var fontSize: CGFloat = 12.5
  var horizontal: CGFloat = 12
  var minHeight: CGFloat = 44
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .ritmFont(fontSize, weight: .semibold)
      .foregroundStyle(prominent ? RitmTheme.ctaInk : RitmTheme.accentColor)
      .padding(.horizontal, horizontal)
      .frame(minHeight: minHeight)
      .background {
        if prominent {
          Capsule().fill(RitmTheme.ctaGradient)
        } else {
          Capsule().fill(RitmTheme.glassRaised)
        }
      }
      .overlay { Capsule().strokeBorder(RitmGlassTokens.rim, lineWidth: RitmGlassTokens.rimWidth) }
      .contentShape(Capsule())
      .scaleEffect(configuration.isPressed && !reduceMotion ? RitmGlassTokens.pressScale : 1)
      .animation(reduceMotion ? nil : RitmMotion.press, value: configuration.isPressed)
      .opacity(isEnabled ? 1 : 0.5)
  }
}

/// Date labels without a `DateFormatter` per call: the page asks for the same few dozen labels on
/// every render (day tiles, bars, heat cells), so each one is formatted once and remembered.
@MainActor
enum HabitDates {
  private static var cache: [String: String] = [:]

  static func label(_ key: String, zone: String, language: Language, template: String) -> String {
    let id = "\(zone)|\(language == .ru)|\(template)|\(key)"
    if let hit = cache[id] { return hit }
    let text = FeatureDate.label(key, zone: zone, language: language, template: template)
    cache[id] = text
    return text
  }

  /// «8–14 нояб.», «30 окт. – 5 нояб.» for a week, «Ноябрь 2026» for a month.
  static func periodLabel(_ dates: [String], month: Bool, zone: String, language: Language)
    -> String
  {
    guard let first = dates.first, let last = dates.last else { return "" }
    func text(_ day: String, _ template: String) -> String {
      label(day, zone: zone, language: language, template: template)
    }
    if month { return text(first, "LLLL yyyy").habitCapitalized }
    if first.prefix(7) == last.prefix(7) { return text(first, "d") + "–" + text(last, "d MMM") }
    return text(first, "d MMM") + " – " + text(last, "d MMM")
  }
}

/// `.pnav .ar`: a 32 pt round arrow with a 44 pt touch area. `tint` colours the glyph and the
/// rim; the default is the calm page style, the analytics card passes its own lavender.
struct HabitArrowButton: View {
  let symbol: String
  let label: String
  var ink: Color = RitmTheme.muted
  var fill: Color = RitmTheme.glassRaised
  var rim: Color = RitmTheme.line
  let action: () -> Void
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button(action: action) {
      RitmSymbol(symbol)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(ink)
        .frame(width: 32, height: 32)
        .background { Circle().fill(fill) }
        .overlay { Circle().strokeBorder(rim, lineWidth: 1) }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .opacity(isEnabled ? 1 : 0.35)
    }
    .buttonStyle(RitmPressStyle())
    .accessibilityLabel(label)
  }
}

/// `.lnk`: the «Тренировки» badge of the habit that workouts tick.
struct HabitLinkBadge: View {
  @Environment(RitmStore.self) private var store

  var body: some View {
    HStack(spacing: 4) {
      RitmSymbol("dumbbell").font(.system(size: 12, weight: .semibold))
      Text(store.text("Тренировки", "Workouts")).ritmFont(11, weight: .semibold, tracking: -0.01)
    }
    .foregroundStyle(RitmTheme.accentColor)
    .padding(.leading, 6)
    .padding(.trailing, 8)
    .frame(height: 20)
    .background(RitmTheme.accentColor.opacity(0.15), in: Capsule())
    .fixedSize()
    .accessibilityElement(children: .combine)
    .accessibilityLabel(store.text("Связана с тренировками", "Linked to workouts"))
  }
}

/// A ring: a round-capped arc over a track, starting at 12 o'clock. The arc sweeps from empty on
/// the first appearance of the page and eases to a new value afterwards (MOTION.md §4); under
/// Reduce Motion it is simply there.
struct HabitProgressRing<Center: View>: View {
  let fraction: Double
  let size: CGFloat
  let lineWidth: CGFloat
  var track: Color = RitmTheme.ringTrack
  var arc: Color = RitmTheme.accentColor
  var glow: Color?
  /// Replays the sweep when it changes.
  var key: String = ""
  @ViewBuilder var center: Center
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let value = min(1, max(0, fraction))
    ZStack {
      Circle().stroke(track, lineWidth: lineWidth)
      RitmDrawGate(key: key) { drawn in
        Circle()
          .trim(from: 0, to: drawn ? value : 0)
          .stroke(arc, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .shadow(color: glow ?? .clear, radius: glow == nil ? 0 : 4)
          .animation(reduceMotion ? nil : RitmMotion.sweep, value: drawn)
          .animation(reduceMotion ? nil : RitmMotion.easeOut(RitmMotion.countChange), value: value)
      }
      center
    }
    .padding(lineWidth / 2)
    .frame(width: size, height: size)
  }
}

/// MOTION.md «period switch»: when `key` changes the content is hidden at once and then fades
/// back in, sliding 16 pt from the side the user is moving to (8 pt up for a plain fade). With
/// Reduce Motion it is a 120 ms fade. The numbers inside keep counting from what they showed.
private struct HabitSwap: ViewModifier {
  let key: String
  let direction: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var settled: String

  init(key: String, direction: CGFloat) {
    self.key = key
    self.direction = direction
    _settled = State(initialValue: key)
  }

  func body(content: Content) -> some View {
    let hidden = settled != key
    content
      .opacity(hidden ? 0 : 1)
      .offset(
        x: hidden && !reduceMotion ? direction * 16 : 0,
        y: hidden && !reduceMotion && direction == 0 ? 8 : 0
      )
      .onChange(of: key) { _, value in
        withAnimation(reduceMotion ? RitmMotion.reducedFade : RitmMotion.easeOut(0.3)) {
          settled = value
        }
      }
  }
}

extension View {
  func habitSwap(key: String, direction: CGFloat = 0) -> some View {
    modifier(HabitSwap(key: key, direction: direction))
  }
}
