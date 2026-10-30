import SwiftUI
import UIKit

// Design tokens from src/styles/tokens.css, visual-refresh.css and navigation-glass.css as they
// resolve at a 390 px viewport. Each colour is a light/dark pair resolved from the trait
// collection, so it follows both the device appearance and the account theme that
// RitmRootView applies with preferredColorScheme. Tokens are computed properties so they stay
// free of shared mutable state under Swift 6 strict concurrency.

extension UIColor {
  convenience init(rgb: UInt32, alpha: Double = 1) {
    self.init(
      red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255, alpha: CGFloat(alpha))
  }
}

extension Color {
  init(rgb: UInt32, opacity: Double = 1) {
    self.init(uiColor: UIColor(rgb: rgb, alpha: opacity))
  }

  init(light: UInt32, dark: UInt32, lightOpacity: Double = 1, darkOpacity: Double = 1) {
    self.init(
      uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
          ? UIColor(rgb: dark, alpha: darkOpacity) : UIColor(rgb: light, alpha: lightOpacity)
      })
  }
}

enum RitmTheme {
  static var background: Color { Color(light: 0xF7F5FB, dark: 0x12101B) }
  static var panel: Color { Color(light: 0xFFFFFF, dark: 0x1D172A) }
  static var text: Color { Color(light: 0x29223B, dark: 0xF1EBFB) }
  static var muted: Color { Color(light: 0x706577, dark: 0xAAA0BA) }
  static var line: Color { Color(light: 0xE8E2F0, dark: 0x352B45) }
  static var accentColor: Color { Color(light: 0x7651BC, dark: 0xB99CEB) }
  static var accentInk: Color { Color(light: 0xFFFFFF, dark: 0x271938) }
  static var soft: Color { Color(light: 0xF0EAF9, dark: 0x30253E) }
  static var field: Color { Color(light: 0xFFFFFF, dark: 0x211A2F) }
  static var ringTrack: Color { Color(light: 0xECE5F3, dark: 0x382B47) }
  static var danger: Color { Color(light: 0xB53654, dark: 0xF59AAF) }
  static var dangerSoft: Color { Color(light: 0xFFF0F3, dark: 0x3B202F) }
  static var success: Color { Color(light: 0x7651BC, dark: 0xC3A7EC) }
  /// `color-mix(in srgb, var(--line) 64%, var(--glass-stroke))` as the browser computes it.
  static var panelBorder: Color {
    Color(light: 0xEFEBF5, dark: 0x3F3451, lightOpacity: 0.946, darkOpacity: 0.683)
  }
  static var glassRaised: Color {
    Color(light: 0xFFFFFF, dark: 0x302642, lightOpacity: 0.9, darkOpacity: 0.94)
  }
  static var glassDense: Color {
    Color(light: 0xFCFAFF, dark: 0x20192D, lightOpacity: 0.96, darkOpacity: 0.97)
  }
  /// `0 7px 22px rgba(44, 24, 72, .08)` in both themes.
  static var panelShadow: Color { Color(rgb: 0x2C1848, opacity: 0.08) }

  // Names kept from the first native draft; they now resolve to the web tokens.
  static var lavender: Color { accentColor }
  static var ink: Color { accentInk }
  static func accent(_ scheme: ColorScheme) -> Color { accentColor }
  static func surface(_ scheme: ColorScheme) -> Color { panel }

  /// `color-mix(in srgb, color share, base)`, resolved per theme.
  static func mix(_ color: Color, _ share: Double, into base: Color) -> Color {
    Color(
      uiColor: UIColor { traits in
        let top = UIColor(color).resolvedColor(with: traits)
        let bottom = UIColor(base).resolvedColor(with: traits)
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        top.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        bottom.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let amount = CGFloat(share)
        return UIColor(
          red: r1 * amount + r2 * (1 - amount), green: g1 * amount + g2 * (1 - amount),
          blue: b1 * amount + b2 * (1 - amount), alpha: a1 * amount + a2 * (1 - amount))
      })
  }

  /// Start and end points of a CSS `linear-gradient(<angle>deg, …)` in a unit box.
  static func points(cssAngle degrees: Double) -> (start: UnitPoint, end: UnitPoint) {
    let radians = degrees * .pi / 180
    let dx = sin(radians) / 2
    let dy = -cos(radians) / 2
    return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
  }

  static func linear(_ stops: [Gradient.Stop], cssAngle: Double) -> LinearGradient {
    let direction = points(cssAngle: cssAngle)
    return LinearGradient(stops: stops, startPoint: direction.start, endPoint: direction.end)
  }

  /// `--title-gradient`, 110°.
  static var titleGradient: LinearGradient {
    linear(
      [
        .init(color: Color(light: 0x4C2B78, dark: 0xF1E5FF), location: 0),
        .init(color: Color(light: 0x8250BA, dark: 0xB999E2), location: 0.65),
        .init(color: Color(light: 0x7E66A9, dark: 0xC1AFE5), location: 1),
      ], cssAngle: 110)
  }

  /// Primary call to action, 125°. The dark theme has two stops on the web; the middle
  /// stop here is their blend at 72 %, so both themes share one gradient shape.
  static var ctaGradient: LinearGradient {
    linear(
      [
        .init(color: Color(light: 0x6540AE, dark: 0xB390E9), location: 0),
        .init(color: Color(light: 0x855ACC, dark: 0xC8A6EF), location: 0.72),
        .init(color: Color(light: 0x8A5EC8, dark: 0xD0AFF1), location: 1),
      ], cssAngle: 125)
  }
  static var ctaInk: Color { Color(light: 0xFFFFFF, dark: 0x21162F) }
  static var ctaShadow: Color { Color(rgb: 0x673FA8, opacity: 0.22) }

  /// The 155° panel sheen that lights the top-left of every card.
  static var panelSheen: LinearGradient {
    linear(
      [
        .init(
          color: Color(light: 0xFFFFFF, dark: 0xDABDFF, lightOpacity: 0.34, darkOpacity: 0.045),
          location: 0),
        .init(color: .clear, location: 0.65),
      ], cssAngle: 155)
  }

  /// Hero cards («Ближайшее событие», finance balance): 139° deep violet.
  static var heroGradient: LinearGradient {
    linear(
      [
        .init(color: Color(rgb: 0x44306B), location: 0),
        .init(color: Color(rgb: 0x6B49A0), location: 0.64),
        .init(color: Color(rgb: 0x8A65B7), location: 1),
      ], cssAngle: 139)
  }
}

// MARK: - Typography

/// Text roles with the web sizes at 390 px. Sizes scale with Dynamic Type through
/// UIFontMetrics, so 27 pt stays 27 pt at the default size, as on the web.
enum RitmTextRole {
  case pageTitle, eyebrow, cardTitle, cardCaption, body, message, button,
    navLabel, brand, footer, sectionTitle, value

  var size: CGFloat {
    switch self {
    case .pageTitle: 27
    case .eyebrow, .cardCaption, .navLabel: 10
    case .cardTitle: 15
    case .body, .button: 12
    case .message: 13
    case .brand, .sectionTitle: 22
    case .footer: 9
    case .value: 25
    }
  }

  var weight: Font.Weight {
    switch self {
    case .pageTitle, .cardTitle, .button, .sectionTitle, .value: .semibold
    // `font-weight: 650` renders with Inter's 700 face.
    case .eyebrow, .brand: .bold
    case .cardCaption, .navLabel: .medium
    case .body, .message, .footer: .regular
    }
  }

  /// Letter spacing in em.
  var tracking: CGFloat {
    switch self {
    case .pageTitle: -0.055
    case .eyebrow: 0.065
    case .cardTitle: -0.025
    case .brand: -0.06
    case .sectionTitle, .value: -0.03
    default: 0
    }
  }

  /// Extra space between lines, from the CSS line-height minus the font's own leading.
  var lineSpacing: CGFloat {
    switch self {
    case .message: 7
    case .body: 3
    default: 0
    }
  }

  var textStyle: UIFont.TextStyle {
    switch self {
    case .pageTitle, .sectionTitle, .brand, .value: .title2
    case .cardTitle: .headline
    case .eyebrow, .cardCaption, .navLabel, .footer: .caption2
    case .body, .message, .button: .subheadline
    }
  }
}

private struct RitmFontModifier: ViewModifier {
  let size: CGFloat
  let weight: Font.Weight
  /// Letter spacing in em.
  let tracking: CGFloat
  let lineSpacing: CGFloat
  let style: UIFont.TextStyle
  @Environment(\.dynamicTypeSize) private var typeSize

  func body(content: Content) -> some View {
    let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
    let scaled = UIFontMetrics(forTextStyle: style).scaledValue(for: size, compatibleWith: traits)
    content
      .font(.custom(RitmFonts.name(weight), fixedSize: scaled))
      .tracking(scaled * tracking)
      .lineSpacing(lineSpacing * scaled / size)
  }
}

extension View {
  func ritmText(_ role: RitmTextRole) -> some View {
    modifier(
      RitmFontModifier(
        size: role.size, weight: role.weight, tracking: role.tracking,
        lineSpacing: role.lineSpacing, style: role.textStyle))
  }

  /// A one-off web size that has no shared role, scaled with Dynamic Type like the roles.
  func ritmFont(
    _ size: CGFloat, weight: Font.Weight = .regular, tracking: CGFloat = 0,
    lineSpacing: CGFloat = 0
  ) -> some View {
    modifier(
      RitmFontModifier(
        size: size, weight: weight, tracking: tracking, lineSpacing: lineSpacing,
        style: size >= 20 ? .title2 : size >= 13 ? .subheadline : .caption1))
  }
}

// MARK: - Surfaces

struct RitmBackground: View {
  @Environment(\.colorScheme) private var scheme

  /// One `radial-gradient(rx ry at x y, colour, transparent fade)` layer, as fractions of the box.
  private struct Glow {
    let color: Color
    let rx: CGFloat
    let ry: CGFloat
    let x: CGFloat
    let y: CGFloat
    let fade: CGFloat
  }

  private var glows: [Glow] {
    scheme == .dark
      ? [
        Glow(color: Color(rgb: 0x804EBB, opacity: 0.23), rx: 0.53, ry: 0.43, x: 0.87, y: 0.07, fade: 0.75),
        Glow(color: Color(rgb: 0x4D3385, opacity: 0.23), rx: 0.39, ry: 0.39, x: 0.13, y: 0.84, fade: 0.77),
      ]
      : [
        Glow(color: Color(rgb: 0x9F74E1, opacity: 0.2), rx: 0.55, ry: 0.43, x: 0.9, y: 0.05, fade: 0.77),
        Glow(color: Color(rgb: 0xD3B6F6, opacity: 0.18), rx: 0.36, ry: 0.36, x: 0.1, y: 0.8, fade: 0.76),
        Glow(color: Color(rgb: 0xE7CFFF, opacity: 0.14), rx: 0.35, ry: 0.24, x: 0.55, y: 0.5, fade: 0.82),
      ]
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        RitmTheme.background
        ForEach(glows.indices, id: \.self) { index in
          let glow = glows[index]
          Rectangle()
            .fill(
              EllipticalGradient(
                stops: [
                  .init(color: glow.color, location: 0),
                  .init(color: glow.color.opacity(0), location: glow.fade),
                ],
                center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
            )
            .frame(width: 2 * glow.rx * proxy.size.width, height: 2 * glow.ry * proxy.size.height)
            .position(x: glow.x * proxy.size.width, y: glow.y * proxy.size.height)
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }
}

/// The opaque mobile panel: fill, 155° sheen, one contour and the soft violet shadow.
struct RitmPanelBackground: View {
  var radius: CGFloat = 23
  var raised = false
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
    shape
      .fill(raised && !reduceTransparency ? RitmTheme.glassRaised : RitmTheme.panel)
      .overlay {
        if !reduceTransparency { shape.fill(RitmTheme.panelSheen) }
      }
      .overlay {
        // One contour; lighting is a fill, never a second inset outline.
        shape.strokeBorder(
          contrast == .increased ? RitmTheme.text : RitmTheme.panelBorder, lineWidth: 1)
      }
      .ritmCalmRim(in: shape)
      .shadow(color: RitmTheme.panelShadow, radius: 11, y: 7)
  }
}

struct RitmCard<Content: View>: View {
  private let content: Content
  private let reveal: Int?
  private let padding: CGFloat
  private let radius: CGFloat
  private let raised: Bool

  init(
    reveal: Int? = nil, padding: CGFloat = 20, radius: CGFloat = 23, raised: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.content = content()
    self.reveal = reveal
    self.padding = padding
    self.radius = radius
    self.raised = raised
  }

  var body: some View {
    let card = content
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background { RitmPanelBackground(radius: radius, raised: raised) }
    if let reveal {
      card.ritmPageReveal(index: reveal)
    } else {
      card
    }
  }
}

// MARK: - Buttons

/// Press feedback (MOTION.md): scale .97 over 130 ms, no opacity change. With Reduce Motion the
/// animation is removed; a slight dimming keeps the press visible without movement.
struct RitmPressStyle: ButtonStyle {
  var scale: CGFloat = RitmMotion.pressScale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
      .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
      .animation(reduceMotion ? nil : RitmMotion.press, value: configuration.isPressed)
  }
}

/// Prominent glass capsule: the accent gradient on a glass base, strong contrast for the label.
struct RitmPrimaryButtonStyle: ButtonStyle {
  var minHeight: CGFloat = 44
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .ritmText(.button)
      .padding(.horizontal, 14)
      .frame(maxWidth: .infinity, minHeight: minHeight)
      .foregroundStyle(RitmTheme.ctaInk)
      .ritmGlass(in: Capsule(), prominent: true, interactive: true)
      .opacity(isEnabled ? 1 : 0.6)
      .environment(\.ritmGlassPressed, configuration.isPressed)
  }
}

/// `.text-button`: accent label without a surface; 44 pt tall on phones (app.css 2030).
struct RitmTextButtonStyle: ButtonStyle {
  var size: CGFloat = 11
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .ritmFont(size, weight: .medium)
      .foregroundStyle(RitmTheme.accentColor)
      .frame(minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
      .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.5)
  }
}

/// Secondary button: a glass capsule with an accent label.
struct RitmSecondaryButtonStyle: ButtonStyle {
  var minHeight: CGFloat = 44
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .ritmText(.button)
      .padding(.horizontal, 14)
      .frame(minHeight: minHeight)
      .foregroundStyle(RitmTheme.accentColor)
      .ritmGlass(in: Capsule(), interactive: true)
      .opacity(isEnabled ? 1 : 0.6)
      .environment(\.ritmGlassPressed, configuration.isPressed)
  }
}

/// The 44 × 44 icon-only call to action next to a page title (DashboardPage «+»): a prominent
/// glass circle.
struct RitmIconCTA: View {
  let symbol: String
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 21, weight: .regular))
        .foregroundStyle(RitmTheme.ctaInk)
        .frame(width: 44, height: 44)
        .ritmGlass(in: Circle(), prominent: true, interactive: true)
        .contentShape(Circle())
    }
    .buttonStyle(RitmGlassButtonStyle())
    .accessibilityLabel(label)
  }
}

// MARK: - Page structure

/// The page heading: the gradient title and an optional action beside it.
struct RitmPageHeading<Action: View>: View {
  let title: String
  private let action: Action

  init(title: String, @ViewBuilder action: () -> Action) {
    self.title = title
    self.action = action()
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Text(title)
        .ritmText(.pageTitle)
        .foregroundStyle(RitmTheme.titleGradient)
        .accessibilityAddTraits(.isHeader)
        .frame(maxWidth: .infinity, alignment: .leading)
      action
    }
    .padding(.top, 6)
    .padding(.bottom, 20)
  }
}

extension RitmPageHeading where Action == EmptyView {
  init(title: String) {
    self.init(title: title) { EmptyView() }
  }
}

/// «Ritm · Меньше шума. Больше ясности.» under every page.
struct RitmPageFooter: View {
  @Environment(RitmStore.self) private var store

  var body: some View {
    HStack {
      Text("Ritm")
      Spacer(minLength: 12)
      Text(store.text("Меньше шума. Больше ясности.", "Less noise. More clarity."))
    }
    .ritmText(.footer)
    .foregroundStyle(RitmTheme.muted)
    .opacity(0.8)
    .padding(.top, 24)
    .accessibilityElement(children: .combine)
  }
}

struct RitmEmptyState: View {
  let symbol: String
  let title: String
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 20))
        .foregroundStyle(RitmTheme.accentColor)
        .accessibilityHidden(true)
      Text(title).ritmText(.cardTitle).foregroundStyle(RitmTheme.text)
      Text(message).ritmText(.body).foregroundStyle(RitmTheme.muted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Web error: danger text on danger-soft, radius 10.
struct RitmErrorBanner: View {
  let message: String

  var body: some View {
    Label {
      Text(message).ritmText(.body).textSelection(.enabled)
    } icon: {
      Image(systemName: "exclamationmark.circle")
    }
    .foregroundStyle(RitmTheme.danger)
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RitmTheme.dangerSoft, in: RoundedRectangle(cornerRadius: 10, style: .circular))
    .accessibilityElement(children: .combine)
  }
}

/// The same four-point silhouette as public/ritm-mark.svg, rendered natively.
struct RitmMark: Shape {
  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width, rect.height) / 64
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: rect.midX + (x - 32) * scale, y: rect.midY + (y - 32) * scale)
    }
    var path = Path()
    path.move(to: point(32, 12))
    path.addCurve(to: point(52, 32), control1: point(35, 24), control2: point(40, 29))
    path.addCurve(to: point(32, 52), control1: point(40, 35), control2: point(35, 40))
    path.addCurve(to: point(12, 32), control1: point(29, 40), control2: point(24, 35))
    path.addCurve(to: point(32, 12), control1: point(24, 29), control2: point(29, 24))
    path.closeSubpath()
    return path
  }
}

private struct RitmPageActiveKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
  var ritmPageActive: Bool {
    get { self[RitmPageActiveKey.self] }
    set { self[RitmPageActiveKey.self] = newValue }
  }
}
