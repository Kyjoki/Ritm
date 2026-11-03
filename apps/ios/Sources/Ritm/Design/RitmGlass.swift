import SwiftUI

// «Liquid Glass» as in the prototype (glass.css). Two layers:
//
// - Controls that FLOAT over scrolling content (bottom bar, header buttons, popovers, banner,
//   toast) are real system glass: `ritmFloatingGlass`, grouped by `GlassEffectContainer`
//   (`RitmGlassGroup`). One layer per control, no extra blur under it.
// - Everything that sits on a calm card (capsule buttons, chips, circular icon buttons, the lit
//   call to action) is `ritmGlass`: a plain fill with a 1.25 pt specular rim (140°, bright at the
//   top-left and bottom-right corners, fading along the sides) and a soft shadow. No blur, so a
//   screen full of buttons stays cheap.
//
// Both press with scale .96 on a spring. Reduce Motion drops the movement, Reduce Transparency
// makes the fills opaque, Increase Contrast draws a plain contour.

// MARK: - Tokens

enum RitmGlassTokens {
  static var rimHigh: Color {
    Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 1, darkOpacity: 0.62)
  }
  static var rimLow: Color {
    Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.4, darkOpacity: 0.10)
  }
  static var inner: Color {
    Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.7, darkOpacity: 0.13)
  }
  static var shine: Color {
    Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.6, darkOpacity: 0.15)
  }
  /// `0 18 40 -14` in the reference: a blur of 20 with the offset pulled in.
  static var shadow: Color {
    Color(light: 0x2C1848, dark: 0x000000, lightOpacity: 0.22, darkOpacity: 0.5)
  }
  /// `--calm-hi` / `--calm-lo`: the inset lit top and shaded bottom line of a calm card.
  static var calmHigh: Color {
    Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.95, darkOpacity: 0.07)
  }
  static var calmLow: Color {
    Color(light: 0x3E236B, dark: 0x000000, lightOpacity: 0.05, darkOpacity: 0.2)
  }
  /// `--lg-btn`: a translucent capsule on a calm card, lit from above.
  static var buttonFill: LinearGradient {
    LinearGradient(
      colors: [
        Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.92, darkOpacity: 0.12),
        Color(light: 0xF3EDFC, dark: 0xFFFFFF, lightOpacity: 0.66, darkOpacity: 0.05),
      ], startPoint: .top, endPoint: .bottom)
  }
  /// `--lg-btn-shadow`, the outer part: `0 6px 14px -8px`.
  static var buttonShadow: Color {
    Color(light: 0x3E236B, dark: 0x000000, lightOpacity: 0.3, darkOpacity: 0.5)
  }
  /// `--lg-cta-shadow`, the outer part: `0 10px 22px -10px`.
  static var ctaGlow: Color {
    Color(light: 0x673FA8, dark: 0x000000, lightOpacity: 0.55, darkOpacity: 0.6)
  }
  /// The corners of a call to action's rim are a little quieter than a plain button's.
  static var ctaRim: LinearGradient {
    let corner = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.85, darkOpacity: 0.7)
    return RitmTheme.linear(
      [
        .init(color: corner, location: 0),
        .init(color: Color.white.opacity(0.14), location: 0.3),
        .init(color: .clear, location: 0.5),
        .init(color: .clear, location: 0.62),
        .init(color: Color.white.opacity(0.14), location: 0.78),
        .init(color: corner, location: 1),
      ], cssAngle: 140)
  }
  /// The glossy veil over a call to action.
  static var ctaVeil: LinearGradient {
    LinearGradient(
      stops: [
        .init(color: Color.white.opacity(0.22), location: 0),
        .init(color: .clear, location: 0.55),
      ], startPoint: .top, endPoint: .bottom)
  }

  static let rimWidth: CGFloat = 1.25
  static let pressScale: CGFloat = 0.96
  /// The reference spring, `cubic-bezier(.34, 1.56, .64, 1)` over .35 s.
  static var pressSpring: Animation { .spring(response: 0.35, dampingFraction: 0.62) }

  /// Specular rim: bright where the light hits, fading along the sides (140°).
  static var rim: LinearGradient {
    RitmTheme.linear(
      [
        .init(color: rimHigh, location: 0),
        .init(color: rimLow, location: 0.26),
        .init(color: .clear, location: 0.48),
        .init(color: .clear, location: 0.58),
        .init(color: rimLow, location: 0.76),
        .init(color: rimHigh, location: 1),
      ], cssAngle: 140)
  }

  /// Soft inner highlights, one under the top edge and a weaker one above the bottom edge.
  static var highlight: LinearGradient {
    LinearGradient(
      stops: [
        .init(color: inner, location: 0),
        .init(color: .clear, location: 0.34),
        .init(color: .clear, location: 0.72),
        .init(color: inner.opacity(0.6), location: 1),
      ], startPoint: .top, endPoint: .bottom)
  }
}

// MARK: - Press state

private struct RitmGlassPressedKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
  /// Set by `RitmGlassButtonStyle`, read by `ritmGlass(interactive: true)` to scale and shine.
  var ritmGlassPressed: Bool {
    get { self[RitmGlassPressedKey.self] }
    set { self[RitmGlassPressedKey.self] = newValue }
  }
}

/// Hands the pressed state to a glass label inside the button. The label does the scaling, so
/// the glass and its content press together.
struct RitmGlassButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.environment(\.ritmGlassPressed, configuration.isPressed)
  }
}

// MARK: - Public API

extension View {
  /// A translucent capsule, chip or icon button on a calm card (prototype `.btn`, `.ghost`), or
  /// with `prominent` the lit accent call to action. A plain fill with a specular rim and a soft
  /// shadow: no blur. `interactive` adds the press response (use it with `RitmGlassButtonStyle`).
  func ritmGlass<S: Shape>(
    in shape: S, prominent: Bool = false, interactive: Bool = false, tint: Color? = nil
  ) -> some View {
    modifier(
      RitmGlassModifier(
        shape: shape, prominent: prominent, interactive: interactive, tint: tint, floating: false))
  }

  /// Real system Liquid Glass for a control that floats over scrolling content: the bottom bar,
  /// the header buttons, popovers, the banner and the toast. One layer per control.
  func ritmFloatingGlass<S: Shape>(
    in shape: S, interactive: Bool = false, tint: Color? = nil
  ) -> some View {
    modifier(
      RitmGlassModifier(
        shape: shape, prominent: false, interactive: interactive, tint: tint, floating: true))
  }

  /// A small raised drop (the chip behind a ghost or close button inside a floating panel). It
  /// has no blur of its own: blurs are not stacked.
  func ritmGlassThumb<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
    modifier(RitmGlassThumbModifier(shape: shape, tint: tint))
  }

  /// The sheet grabber: the system drag indicator.
  func ritmSheetGrabber() -> some View {
    modifier(RitmSheetGrabberModifier())
  }

  /// A hairline specular rim for calm content cards.
  func ritmCalmRim<S: Shape>(in shape: S) -> some View {
    overlay { RitmCalmRim(shape: shape) }
  }
}

/// Groups neighbouring glass controls so the system can merge and morph them.
struct RitmGlassGroup<Content: View>: View {
  var spacing: CGFloat = 12
  @ViewBuilder var content: Content

  var body: some View {
    GlassEffectContainer(spacing: spacing) { content }
  }
}

// MARK: - Modifier

private struct RitmGlassModifier<S: Shape>: ViewModifier {
  let shape: S
  let prominent: Bool
  let interactive: Bool
  let tint: Color?
  let floating: Bool
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.ritmGlassPressed) private var pressed

  func body(content: Content) -> some View {
    if floating && !reduceTransparency {
      native(content)
    } else {
      plain(content)
    }
  }

  private func native(_ content: Content) -> some View {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return content.glassEffect(glass, in: shape)
  }

  /// A plain fill: the prototype's capsule, call to action, or (Reduce Transparency) an opaque
  /// panel.
  private func plain(_ content: Content) -> some View {
    let active = interactive && pressed
    return content
      .background {
        RitmGlassSurface(shape: shape, prominent: prominent, tint: tint, sheen: active)
      }
      .scaleEffect(active && !reduceMotion ? RitmGlassTokens.pressScale : 1)
      .animation(reduceMotion ? nil : RitmGlassTokens.pressSpring, value: active)
  }
}

private struct RitmGlassThumbModifier<S: Shape>: ViewModifier {
  let shape: S
  let tint: Color?

  func body(content: Content) -> some View {
    content.background {
      RitmGlassSurface(shape: shape, prominent: false, tint: tint, sheen: false)
    }
  }
}

/// The 1.25 pt rim drawn inside the shape: a 2.5 pt centred stroke clipped to the shape.
@ViewBuilder
private func rim<S: Shape>(_ shape: S, contrast: ColorSchemeContrast, quiet: Bool = false)
  -> some View
{
  if contrast == .increased {
    shape.stroke(RitmTheme.text, lineWidth: 2).clipShape(shape)
  } else {
    shape
      .stroke(
        quiet ? RitmGlassTokens.ctaRim : RitmGlassTokens.rim,
        lineWidth: RitmGlassTokens.rimWidth * 2
      )
      .clipShape(shape)
  }
}

private struct RitmSheetGrabberModifier: ViewModifier {
  func body(content: Content) -> some View {
    content.presentationDragIndicator(.visible)
  }
}

// MARK: - Plain surface

private struct RitmGlassSurface<S: Shape>: View {
  let shape: S
  let prominent: Bool
  let tint: Color?
  let sheen: Bool
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    ZStack {
      if prominent {
        shape.fill(RitmTheme.ctaGradient)
          .shadow(color: RitmGlassTokens.ctaGlow, radius: 9, y: 8)
        if !reduceTransparency { shape.fill(RitmGlassTokens.ctaVeil) }
      } else if reduceTransparency {
        shape.fill(RitmTheme.glassDense)
          .shadow(color: RitmGlassTokens.buttonShadow, radius: 6, y: 5)
      } else {
        shape.fill(RitmGlassTokens.buttonFill)
          .shadow(color: RitmGlassTokens.buttonShadow, radius: 6, y: 5)
      }
      if let tint { shape.fill(tint) }
      if sheen {
        shape.fill(
          RadialGradient(
            colors: [RitmGlassTokens.shine, .clear], center: UnitPoint(x: 0.5, y: 0.1),
            startRadius: 0, endRadius: 90))
      }
      rim(shape, contrast: contrast, quiet: prominent)
    }
  }
}

// MARK: - Calm card rim

/// `inset 0 1px 0 var(--calm-hi), inset 0 -1px 0 var(--calm-lo)`: a lit line under the top edge
/// and a shaded one above the bottom edge, as one gradient stroke clipped to the card.
struct RitmCalmRim<S: Shape>: View {
  let shape: S
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    if !reduceTransparency {
      shape
        .stroke(
          LinearGradient(
            stops: [
              .init(color: RitmGlassTokens.calmHigh, location: 0),
              .init(color: .clear, location: 0.1),
              .init(color: .clear, location: 0.9),
              .init(color: RitmGlassTokens.calmLow, location: 1),
            ], startPoint: .top, endPoint: .bottom),
          lineWidth: 2
        )
        .clipShape(shape)
        .allowsHitTesting(false)
    }
  }
}

// MARK: - Scroll edge

/// Content softens as it slides under a floating bar (MOTION.md §7, glass.css §7): a gradient of
/// the page background. `top` is `--bar-solid` solid down to 60 % of its height and then
/// fading out, `bottom` is `.edge-bot`, a 132 pt veil that fades in towards the home indicator.
/// A plain gradient: no live blur, so scrolling stays cheap.
struct RitmScrollEdge: View {
  enum Side { case top, bottom }
  var side: Side = .top
  var fade: CGFloat = 18
  /// `bottom`: how far below the view the screen edge lies (the home indicator's safe area).
  var bottomInset: CGFloat = 0
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  private var solid: Color {
    reduceTransparency
      ? RitmTheme.background
      : Color(light: 0xF7F5FB, dark: 0x12101B, lightOpacity: 0.86, darkOpacity: 0.82)
  }

  private var veil: Color {
    reduceTransparency
      ? RitmTheme.background
      : Color(light: 0xF7F5FB, dark: 0x12101B, lightOpacity: 0.8, darkOpacity: 0.78)
  }

  var body: some View {
    Group {
      if side == .top {
        LinearGradient(
          stops: [
            .init(color: solid, location: 0),
            .init(color: solid, location: 0.6),
            .init(color: solid.opacity(0), location: 1),
          ], startPoint: .top, endPoint: .bottom
        )
        .padding(.bottom, -fade)
        .ignoresSafeArea(edges: .top)
      } else {
        // `linear-gradient(transparent, edge-fade 58%)` under a mask that is clear at the top
        // and opaque from 42 %, multiplied out into one gradient.
        LinearGradient(
          stops: [
            .init(color: veil.opacity(0), location: 0),
            .init(color: veil.opacity(0.16), location: 0.2),
            .init(color: veil.opacity(0.72), location: 0.42),
            .init(color: veil, location: 0.58),
            .init(color: veil, location: 1),
          ], startPoint: .top, endPoint: .bottom
        )
        .frame(height: 132)
        .offset(y: bottomInset)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
