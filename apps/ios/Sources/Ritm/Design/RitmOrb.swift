import SwiftUI

/// The assistant orb (src/components/Orb.tsx, app.css .ritm-orb): a conic lavender ring that
/// turns once every 18 s around a dark violet core. Reduce Motion stops the rotation.
struct RitmOrb: View {
  var size: CGFloat = 43
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var turning = false

  /// The core is inset 6 pt on the 43 pt orb and 5 pt on the small one.
  private var inset: CGFloat { size < 40 ? 5 : 6 }

  var body: some View {
    ZStack {
      Circle()
        .fill(
          AngularGradient(
            colors: [
              Color(rgb: 0xB59AFE), Color(rgb: 0xD6BCFF), Color(rgb: 0xA8A2ED),
              Color(rgb: 0xC7A8F5), Color(rgb: 0xB59AFE),
            ], center: .center)
        )
        .rotationEffect(.degrees(turning ? 360 : 0))
      Circle()
        .fill(
          RadialGradient(
            stops: [
              .init(color: Color(rgb: 0x614481), location: 0),
              .init(color: Color(rgb: 0x261A39), location: 0.76),
            ], center: UnitPoint(x: 0.33, y: 0.3), startRadius: 0,
            endRadius: (size - 2 * inset) * 0.95)
        )
        .overlay(Circle().stroke(Color(rgb: 0xDABDF7, opacity: 0.18), lineWidth: 1).blur(radius: 2))
        .padding(inset)
    }
    .frame(width: size, height: size)
    .shadow(color: Color(rgb: 0xB48CE3, opacity: 0.26), radius: 11)
    .accessibilityHidden(true)
    .onAppear { startTurning() }
    .onChange(of: reduceMotion) { _, _ in startTurning() }
  }

  private func startTurning() {
    guard !reduceMotion else {
      var still = Transaction()
      still.disablesAnimations = true
      withTransaction(still) { turning = false }
      return
    }
    withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) { turning = true }
  }
}
