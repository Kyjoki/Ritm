import SwiftUI

// «Liquid Glass» for the floating controls (bottom bar, header buttons, popovers, toasts,
// segmented controls, capsule buttons, chips). Content cards stay calm (RitmCard).
//
// On iOS 26 and later `ritmGlass` is the system `glassEffect`, grouped by `GlassEffectContainer`
// (`RitmGlassGroup`). On iOS 17 to 25 it is an emulation of the owner's «Стекло Edge» recipe:
// a thin material, a light tint, soft inner highlights top and bottom, a 1.25 pt specular rim
// (140°, bright at the top-left and bottom-right corners, fading along the sides), a soft outer
// shadow, and a press response (scale .96 on a spring plus a sheen). Metal shaders are not used,
// so the emulation has no refraction. Reduce Transparency draws a solid raised panel with the
// same rim; Reduce Motion drops the press movement; Increase Contrast draws a plain contour.

// MARK: - Tokens

enum RitmGlassTokens {
  /// Light translucent fill: .32 dark, .55 light (higher so text on it stays readable).
  static var fill: Color {
    Color(light: 0xFFFFFF, dark: 0x1D172A, lightOpacity: 0.55, darkOpacity: 0.32)
  }
  /// The sliding thumb inside a glass control.
  static var thumb: Color {
    Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.85, darkOpacity: 0.13)
  }
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
  /// The calm card rim, `--calm-edge`.
  static var calmEdge: Color {
    Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 1, darkOpacity: 0.16)
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
  /// Liquid Glass on a floating control. `prominent` is the accent call to action,
  /// `interactive` adds the press response (use it with `RitmGlassButtonStyle`).
  func ritmGlass<S: Shape>(
    in shape: S, prominent: Bool = false, interactive: Bool = false, tint: Color? = nil
  ) -> some View {
    modifier(RitmGlassModifier(shape: shape, prominent: prominent, interactive: interactive, tint: tint))
  }

  /// The glass drop that slides under the labels of a segmented control or a tab bar. It has no
  /// blur of its own: it sits on a glass control, and blurs are not stacked.
  func ritmGlassThumb<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
    modifier(RitmGlassThumbModifier(shape: shape, tint: tint))
  }

  /// The sheet grabber: the system indicator on iOS 26, a small glass capsule before it.
  func ritmSheetGrabber() -> some View {
    modifier(RitmSheetGrabberModifier())
  }

  /// A hairline specular rim for calm content cards.
  func ritmCalmRim<S: Shape>(in shape: S) -> some View {
    overlay { RitmCalmRim(shape: shape) }
  }
}

/// Groups neighbouring glass controls so the system can merge and morph them on iOS 26+;
/// a plain container on older systems.
struct RitmGlassGroup<Content: View>: View {
  var spacing: CGFloat = 12
  @ViewBuilder var content: Content

  var body: some View {
    if #available(iOS 26.0, *) {
      GlassEffectContainer(spacing: spacing) { content }
    } else {
      content
    }
  }
}

// MARK: - Modifier

private struct RitmGlassModifier<S: Shape>: ViewModifier {
  let shape: S
  let prominent: Bool
  let interactive: Bool
  let tint: Color?
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.ritmGlassPressed) private var pressed

  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      if reduceTransparency {
        emulated(content)
      } else {
        native(content)
      }
    } else {
      emulated(content)
    }
  }

  @available(iOS 26.0, *)
  private func native(_ content: Content) -> some View {
    var glass = Glass.regular
    if prominent {
      glass = glass.tint(RitmTheme.accentColor.opacity(0.5))
    } else if let tint {
      glass = glass.tint(tint)
    }
    if interactive { glass = glass.interactive() }
    // The accent gradient keeps the label of a prominent button at full contrast.
    return content
      .background {
        if prominent { shape.fill(RitmTheme.ctaGradient.opacity(0.94)) }
      }
      .glassEffect(glass, in: shape)
  }

  private func emulated(_ content: Content) -> some View {
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
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  func body(content: Content) -> some View {
    content.background {
      if #available(iOS 26.0, *), !reduceTransparency {
        Color.clear.glassEffect(
          tint.map { Glass.regular.tint($0) } ?? Glass.regular, in: shape)
      } else {
        thumb
      }
    }
  }

  private var thumb: some View {
    ZStack {
      shape.fill(reduceTransparency ? RitmTheme.glassDense : RitmGlassTokens.thumb)
      if let tint { shape.fill(tint) }
      shape.fill(RitmGlassTokens.highlight)
      rim(shape, contrast: contrast)
    }
    .shadow(color: RitmGlassTokens.shadow.opacity(0.5), radius: 5, y: 3)
  }
}

/// The 1.25 pt rim drawn inside the shape: a 2.5 pt centred stroke clipped to the shape.
@ViewBuilder
private func rim<S: Shape>(_ shape: S, contrast: ColorSchemeContrast) -> some View {
  if contrast == .increased {
    shape.stroke(RitmTheme.text, lineWidth: 2).clipShape(shape)
  } else {
    shape.stroke(RitmGlassTokens.rim, lineWidth: RitmGlassTokens.rimWidth * 2).clipShape(shape)
  }
}

private struct RitmSheetGrabberModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content.presentationDragIndicator(.visible)
    } else {
      content
        .presentationDragIndicator(.hidden)
        .overlay(alignment: .top) {
          Color.clear
            .frame(width: 36, height: 5)
            .background(RitmTheme.muted.opacity(0.4), in: Capsule())
            .ritmGlass(in: Capsule())
            .padding(.top, 6)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }
  }
}

// MARK: - Emulated surface

private struct RitmGlassSurface<S: Shape>: View {
  let shape: S
  let prominent: Bool
  let tint: Color?
  let sheen: Bool
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    ZStack {
      if prominent {
        shape.fill(RitmTheme.ctaGradient)
      } else if reduceTransparency {
        shape.fill(RitmTheme.glassDense)
      } else {
        shape.fill(.ultraThinMaterial)
        shape.fill(RitmGlassTokens.fill)
      }
      if let tint { shape.fill(tint) }
      if !reduceTransparency || prominent {
        shape.fill(RitmGlassTokens.highlight).opacity(prominent ? 0.7 : 1)
      }
      if sheen {
        shape.fill(
          RadialGradient(
            colors: [RitmGlassTokens.shine, .clear], center: UnitPoint(x: 0.5, y: 0.1),
            startRadius: 0, endRadius: 90))
      }
      rim(shape, contrast: contrast)
    }
    .shadow(
      color: prominent ? RitmTheme.ctaShadow : RitmGlassTokens.shadow, radius: 14, y: 9)
  }
}

// MARK: - Calm card rim

struct RitmCalmRim<S: Shape>: View {
  let shape: S
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    if !reduceTransparency {
      shape
        .stroke(
          RitmTheme.linear(
            [
              .init(color: RitmGlassTokens.calmEdge, location: 0),
              .init(color: .clear, location: 0.3),
              .init(color: .clear, location: 0.8),
              .init(color: RitmGlassTokens.calmEdge, location: 1),
            ], cssAngle: 160),
          lineWidth: 2
        )
        .clipShape(shape)
        .opacity(0.55)
        .allowsHitTesting(false)
    }
  }
}

// MARK: - Scroll edge

/// Content softens as it slides under a floating bar: a gradient of the page background over a
/// thin material, faded out beyond the bar (MOTION.md §7). `top` reaches under the status bar,
/// `bottom` under the home indicator.
struct RitmScrollEdge: View {
  enum Side { case top, bottom }
  var side: Side = .top
  var fade: CGFloat = 18
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    let towardsBar: (UnitPoint, UnitPoint) =
      side == .top ? (.top, .bottom) : (.bottom, .top)
    ZStack {
      if !reduceTransparency { Rectangle().fill(.ultraThinMaterial) }
      LinearGradient(
        colors: [
          RitmTheme.background.opacity(reduceTransparency ? 1 : 0.94),
          RitmTheme.background.opacity(reduceTransparency ? 1 : 0.8),
        ], startPoint: towardsBar.0, endPoint: towardsBar.1)
    }
    .mask {
      VStack(spacing: 0) {
        if side == .bottom {
          LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
            .frame(height: fade)
        }
        Rectangle()
        if side == .top {
          LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: fade)
        }
      }
    }
    .padding(side == .top ? .bottom : .top, -fade)
    .ignoresSafeArea(edges: side == .top ? .top : .bottom)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
