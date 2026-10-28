import SwiftUI

/// The same four-point silhouette as public/ritm-mark.svg, rendered natively.

/// A single entrance per retained view. Data updates and tab returns do not replay it.
enum RitmTheme {
  static let lavender = Color(red: 0.67, green: 0.50, blue: 0.91)
  static let ink = Color(red: 0.16, green: 0.10, blue: 0.25)

  static func accent(_ scheme: ColorScheme) -> Color {
    scheme == .dark
      ? Color(red: 0.78, green: 0.66, blue: 0.98)
      : Color(red: 0.42, green: 0.24, blue: 0.67)
  }

  static func surface(_ scheme: ColorScheme) -> Color {
    scheme == .dark
      ? Color(red: 0.15, green: 0.12, blue: 0.21)
      : Color(red: 0.98, green: 0.96, blue: 1)
  }
}
struct RitmBackground: View {
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    ZStack {
      (scheme == .dark
        ? Color(red: 0.065, green: 0.05, blue: 0.10)
        : Color(red: 0.95, green: 0.93, blue: 0.98))
      RadialGradient(
        colors: [RitmTheme.lavender.opacity(scheme == .dark ? 0.18 : 0.20), .clear],
        center: .topTrailing,
        startRadius: 12,
        endRadius: 520
      )
    }
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }
}
struct RitmCard<Content: View>: View {
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  private let content: Content
  private let entranceDelay: Double

  init(delay: Double = 0, @ViewBuilder content: () -> Content) {
    self.content = content()
    self.entranceDelay = delay
  }

  var body: some View {
    content
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        shape
          .fill(
            reduceTransparency || contrast == .increased
              ? AnyShapeStyle(RitmTheme.surface(scheme))
              : AnyShapeStyle(.ultraThinMaterial)
          )
          .overlay {
            shape.fill(
              LinearGradient(
                colors: [RitmTheme.lavender.opacity(0.08), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              ))
          }
          .overlay {
            // One contour; lighting is a fill, never a second inset outline.
            shape.strokeBorder(
              scheme == .dark
                ? Color.white.opacity(contrast == .increased ? 0.55 : 0.14)
                : RitmTheme.lavender.opacity(contrast == .increased ? 0.65 : 0.22),
              lineWidth: 1
            )
          }
          .shadow(color: .black.opacity(scheme == .dark ? 0.12 : 0.035), radius: 16, y: 6)
      }
      .modifier(RitmEntrance(delay: entranceDelay))
  }
}
struct RitmPressStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.72 : 1)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .animation(
        reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 1),
        value: configuration.isPressed)
  }
}
struct RitmPrimaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .frame(maxWidth: .infinity, minHeight: 50)
      .foregroundStyle(RitmTheme.ink)
      .background(
        RitmTheme.lavender.gradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous)
      )
      .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .animation(
        reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 1),
        value: configuration.isPressed)
  }
}
struct RitmEmptyState: View {
  let symbol: String
  let title: String
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Image(systemName: symbol)
        .font(.title2)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
      Text(title).font(.headline)
      Text(message).font(.subheadline).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct RitmErrorBanner: View {
  let message: String

  var body: some View {
    Label {
      Text(message).font(.subheadline).textSelection(.enabled)
    } icon: {
      Image(systemName: "exclamationmark.circle")
    }
    .foregroundStyle(.primary)
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    .accessibilityElement(children: .combine)
  }
}
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
struct RitmEntrance: ViewModifier {
  @Environment(\.ritmPageActive) private var active
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var introduced = false
  var delay: Double = 0
  func body(content: Content) -> some View {
    content.opacity(introduced || reduceMotion ? 1 : 0)
      .offset(y: introduced || reduceMotion ? 0 : 7)
      .onAppear { enter() }
      .onChange(of: active) { _, _ in enter() }
  }
  private func enter() {
    guard active, !introduced else { return }
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24).delay(delay)) { introduced = true }
  }
}
