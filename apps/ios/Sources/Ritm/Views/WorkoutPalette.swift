import RitmCore
import SwiftUI

/// The colours of «Тренировки» that are not part of the shared theme: the six program gradients
/// (`--k-main` … `--k-amb`, 140°, the same in both themes), the muscle chip colours
/// (`--c0` … `--c5`) and a few accents of the workout screens.
enum WorkoutPalette {
  private static let gradients: [[UInt32]] = [
    [0x55309F, 0x6D46C2, 0x8860DA],
    [0x263891, 0x4058BD, 0x5E78E0],
    [0x66217F, 0x96418F, 0xBB5FA8],
    [0x08505A, 0x1C7D6E, 0x2C9580],
    [0x232F48, 0x44588A, 0x6279AE],
    [0x6B3F1C, 0xA5682F, 0xC58D4F],
  ]

  static func gradient(_ index: Int) -> LinearGradient {
    let colors = gradients[min(max(index, 0), gradients.count - 1)]
    return RitmTheme.linear(
      [
        .init(color: Color(rgb: colors[0]), location: 0),
        .init(color: Color(rgb: colors[1]), location: 0.6),
        .init(color: Color(rgb: colors[2]), location: 1),
      ], cssAngle: 140)
  }

  /// The mid stop, for tinting a small thing with the program's colour.
  static func accent(_ index: Int) -> Color {
    Color(rgb: gradients[min(max(index, 0), gradients.count - 1)][1])
  }

  static func color(_ muscle: WorkoutMuscle) -> Color {
    switch muscle {
    case .chest: Color(rgb: 0x9C77DB)
    case .triceps: Color(rgb: 0xD798BC)
    case .shoulders: Color(rgb: 0x77A6D4)
    case .back: Color(rgb: 0x79B8A7)
    case .biceps: Color(rgb: 0xD7AD76)
    case .legs: Color(rgb: 0xB79CB6)
    case .abs: Color(rgb: 0x79B8A7)
    }
  }

  /// `--c4`: the star of a record and the flame of a streak.
  static var gold: Color { Color(rgb: 0xD7AD76) }
  static var flame: Color { Color(rgb: 0xE9A35C) }
  /// `--income-bg`: a done set row.
  static var incomeSoft: Color {
    Color(light: 0x74BD9E, dark: 0x74BD9E, lightOpacity: 0.18, darkOpacity: 0.18)
  }
  /// The progress bar of the exercise strip, `#6d46c2 → #d798bc`.
  static var progressGradient: LinearGradient {
    LinearGradient(
      colors: [Color(rgb: 0x6D46C2), Color(rgb: 0xD798BC)], startPoint: .leading, endPoint: .trailing)
  }
  /// `--glass-inset`: a calm inset well.
  static var inset: Color {
    Color(light: 0xEBE2F8, dark: 0x1E162B, lightOpacity: 0.62, darkOpacity: 0.7)
  }
  static var stroke: Color {
    Color(light: 0xEBE5F3, dark: 0xD8BCFF, lightOpacity: 1, darkOpacity: 0.12)
  }
}

/// A program card background: the gradient, a white glow at the top right, a faint rim and a
/// soft drop. One flat layer, no blur.
struct WorkoutGradientSurface: View {
  let colorIndex: Int
  var radius: CGFloat = 20
  var lifted = true

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    shape
      .fill(WorkoutPalette.gradient(colorIndex))
      .overlay {
        shape.fill(
          EllipticalGradient(
            stops: [
              .init(color: Color.white.opacity(0.3), location: 0),
              .init(color: Color.white.opacity(0), location: 1),
            ], center: UnitPoint(x: 0.94, y: 0), startRadiusFraction: 0, endRadiusFraction: 0.6))
      }
      .overlay { shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 1) }
      .shadow(color: .black.opacity(lifted ? 0.4 : 0), radius: 10, y: 8)
  }
}

/// `.mc`: the muscle group chip.
struct WorkoutMuscleChip: View {
  @Environment(RitmStore.self) private var store
  let muscle: WorkoutMuscle

  var body: some View {
    let tint = WorkoutPalette.color(muscle)
    Text(muscle.title(language: store.language))
      .ritmFont(11, weight: .semibold)
      .foregroundStyle(RitmTheme.mix(tint, 0.72, into: RitmTheme.text))
      .padding(.horizontal, 9)
      .frame(height: 22)
      .background(tint.opacity(0.2), in: Capsule())
  }
}

/// A ring from the top: a track and a rounded arc.
struct WorkoutRing: View {
  let progress: Double
  var lineWidth: CGFloat = 8
  var track: Color = RitmTheme.ringTrack
  var tint: Color = RitmTheme.accentColor

  var body: some View {
    ZStack {
      Circle().stroke(track, lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: min(1, max(0, progress)))
        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
    .padding(lineWidth / 2)
    .accessibilityHidden(true)
  }
}

/// A flat, tinted tile with a letter: the badge of a program in lists.
struct WorkoutLetterTile: View {
  let name: String
  var size: CGFloat = 34
  var radius: CGFloat = 11

  var body: some View {
    Text(String(name.first(where: { $0.isLetter || $0.isNumber }) ?? "•").uppercased())
      .ritmFont(size * 0.42, weight: .bold)
      .foregroundStyle(RitmTheme.accentColor)
      .frame(width: size, height: size)
      .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
  }
}

/// Formats for numbers on these screens, cached so a list does not rebuild formatters.
enum WorkoutNumbers {
  private static let ru = formatter("ru_RU")
  private static let en = formatter("en_US")

  private static func formatter(_ id: String) -> NumberFormatter {
    let f = NumberFormatter()
    f.locale = Locale(identifier: id)
    f.numberStyle = .decimal
    f.maximumFractionDigits = 1
    f.minimumFractionDigits = 0
    return f
  }

  /// «14,1 т» from a ton, «840 кг» below.
  static func volume(_ kilograms: Double, russian: Bool) -> String {
    if kilograms >= 1000 {
      let tons = (ru.string(from: NSNumber(value: (kilograms / 100).rounded() / 10)) ?? "0")
      let text = russian ? tons : (en.string(from: NSNumber(value: (kilograms / 100).rounded() / 10)) ?? tons)
      return text + "\u{00A0}" + (russian ? "т" : "t")
    }
    return WorkoutText.kilograms(kilograms, russian: russian)
  }
}
