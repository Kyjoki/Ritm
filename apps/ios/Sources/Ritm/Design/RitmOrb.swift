import SwiftUI

/// The assistant orb as the prototype draws it: a still sphere. The small one (Мой день, the
/// assistant's thinking row) is `radial-gradient(circle at 35% 28%, #f1e3ff, #b58cf0 50%,
/// #6a42a5)` with a short violet shadow; the large one (the assistant's header) is a lavender to
/// blue diagonal with a rose glow at the bottom right and a white highlight at the top left.
/// Nothing turns or floats, so the orb costs no frames while idle.
struct RitmOrb: View {
  var size: CGFloat = 43

  private var large: Bool { size >= 40 }

  var body: some View {
    Group {
      if large { largeSphere } else { smallSphere }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private var smallSphere: some View {
    Circle()
      .fill(
        RadialGradient(
          stops: [
            .init(color: Color(rgb: 0xF1E3FF), location: 0),
            .init(color: Color(rgb: 0xB58CF0), location: 0.5),
            .init(color: Color(rgb: 0x6A42A5), location: 1),
          ], center: UnitPoint(x: 0.35, y: 0.28), startRadius: 0, endRadius: size * 0.97)
      )
      .shadow(color: Color(rgb: 0x6A42A5, opacity: 0.35), radius: 5, y: 4)
  }

  /// `--c0` #9c77db, `--c1` #d798bc, `--c2` #77a6d4.
  private var largeSphere: some View {
    let shape = Circle()
    return shape
      .fill(
        LinearGradient(
          colors: [Color(rgb: 0x9C77DB), Color(rgb: 0x77A6D4)],
          startPoint: UnitPoint(x: 0.17, y: 0.1), endPoint: UnitPoint(x: 0.83, y: 0.9))
      )
      .overlay {
        shape.fill(
          RadialGradient(
            stops: [
              .init(color: Color(rgb: 0xD798BC), location: 0),
              .init(color: Color(rgb: 0xD798BC, opacity: 0), location: 1),
            ], center: UnitPoint(x: 0.7, y: 0.75), startRadius: 0, endRadius: size * 0.615))
      }
      .overlay {
        shape.fill(
          RadialGradient(
            stops: [
              .init(color: .white, location: 0),
              .init(color: Color.white.opacity(0), location: 1),
            ], center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: size * 0.277))
      }
      .overlay { shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 1) }
      .shadow(color: Color(rgb: 0x9C77DB, opacity: 0.45), radius: 11, y: 8)
  }
}
