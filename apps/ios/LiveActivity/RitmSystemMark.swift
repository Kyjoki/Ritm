import SwiftUI

/// The existing Ritm mark, traced from public/ritm-icon.svg, without changing the app icon.
struct RitmSystemMark: View {
  var size: CGFloat = 18
  var body: some View {
    RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
      .fill(LinearGradient(
        colors: [Color(red: 229 / 255, green: 215 / 255, blue: 1),
                 Color(red: 196 / 255, green: 171 / 255, blue: 235 / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing))
      .overlay {
        RitmStar().fill(Color(red: 52 / 255, green: 35 / 255, blue: 76 / 255))
      }
      .frame(width: size, height: size).accessibilityHidden(true)
  }
}

private struct RitmStar: Shape {
  func path(in rect: CGRect) -> Path {
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: rect.minX + x / 64 * rect.width, y: rect.minY + y / 64 * rect.height)
    }
    var path = Path()
    path.move(to: p(32, 12))
    path.addCurve(to: p(52, 32), control1: p(35, 24), control2: p(40, 29))
    path.addCurve(to: p(32, 52), control1: p(40, 35), control2: p(35, 40))
    path.addCurve(to: p(12, 32), control1: p(29, 40), control2: p(24, 35))
    path.addCurve(to: p(32, 12), control1: p(24, 29), control2: p(29, 24))
    path.closeSubpath()
    return path
  }
}
