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
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .ritmFont(fontSize, weight: .semibold)
      .foregroundStyle(prominent ? RitmTheme.ctaInk : RitmTheme.accentColor)
      .padding(.horizontal, horizontal)
      .frame(minHeight: 44)
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
}
