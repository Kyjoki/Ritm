import RitmCore
import SwiftUI

/// The colours of one habit: a palette accent (`--c0…c5` of the prototype, the same in both
/// themes) and the tints that the cards, tiles and buttons derive from it with `color-mix`.
struct HabitTint {
  let base: Color
  /// The icon tile: `color-mix(hc 24%, panel)`.
  let tile: Color
  let tileRim: Color
  /// A completed card: `color-mix(hc 13%, panel)` with a `hc 40%` contour.
  let doneCard: Color
  let doneBorder: Color
  /// `.l2-do`: the soft «Выполнить» footer, and the same once the habit is done.
  let button: Color
  let buttonDone: Color
  let buttonRim: Color
  /// The empty tile of the week strip: a hairline that leans toward the habit's colour.
  let tileBorder: Color
  let partBorder: Color
  let partFill: Color
  /// `.hs-st`, `.hs-cap`: a quiet tinted panel inside the habit sheet.
  let panel: Color
  let panelBorder: Color

  @MainActor
  fileprivate init(_ base: Color) {
    self.base = base
    tile = RitmTheme.mix(base, 0.24, into: RitmTheme.panel)
    tileRim = base.opacity(0.30)
    doneCard = RitmTheme.mix(base, 0.13, into: RitmTheme.panel)
    doneBorder = RitmTheme.mix(base, 0.40, into: RitmTheme.line)
    button = RitmTheme.mix(base, 0.20, into: RitmTheme.panel)
    buttonDone = RitmTheme.mix(base, 0.30, into: RitmTheme.panel)
    buttonRim = base.opacity(0.38)
    tileBorder = RitmTheme.mix(RitmTheme.line, 0.85, into: base)
    partBorder = RitmTheme.mix(base, 0.48, into: RitmTheme.line)
    partFill = base.opacity(0.58)
    panel = RitmTheme.mix(base, 0.11, into: RitmTheme.panel)
    panelBorder = RitmTheme.mix(base, 0.26, into: RitmTheme.line)
  }
}

/// Palette and the surfaces shared by the habit views.
@MainActor
enum HabitPalette {
  /// Violet, blue, teal, pink, amber, grey-lilac.
  static let tints: [HabitTint] = ([0x9C77DB, 0x77A6D4, 0x79B8A7, 0xD798BC, 0xD7AD76, 0xB79CB6] as [UInt32])
    .map { HabitTint(Color(rgb: $0)) }

  static func tint(for habitID: String) -> HabitTint {
    tints[HabitAnalytics.accentIndex(for: habitID) % tints.count]
  }

  /// The ink on a filled tile (`--ink`).
  static let ink = Color(rgb: 0x1A1128)
  /// The streak flame (`--c4`).
  static let flame = Color(rgb: 0xD7AD76)
  /// `--tile`: `color-mix(soft 38%, panel)`.
  static let tile = RitmTheme.mix(RitmTheme.soft, 0.38, into: RitmTheme.panel)
  /// `--glass-surface`: a card in the list.
  static let surface = Color(light: 0xFAF7FF, dark: 0x271F37, lightOpacity: 0.72, darkOpacity: 0.76)
}

/// Compact number with a narrow no-break space between thousands: «1 250».
func habitNumber(_ value: Int) -> String {
  let digits = String(abs(value))
  var grouped = ""
  for (index, character) in digits.reversed().enumerated() {
    if index > 0 && index % 3 == 0 { grouped.append("\u{202F}") }
    grouped.append(character)
  }
  return (value < 0 ? "-" : "") + String(grouped.reversed())
}

/// Short weekday names, Sunday first.
enum HabitWeekdays {
  static func short(_ weekday: Int, language: Language) -> String {
    (language == .ru
      ? ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
      : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])[weekday % 7]
  }
}

extension String {
  /// The first letter in capitals: Russian date templates give «ноябрь», the page wants «Ноябрь».
  var habitCapitalized: String { prefix(1).uppercased() + dropFirst() }
}

/// A line of text with some words in bold, such as «Выполнено 3 из 4 дней».
func habitRichText(_ parts: [(String, Bool)], emphasis: Color) -> Text {
  var result = AttributedString()
  for (text, bold) in parts {
    var piece = AttributedString(text)
    if bold {
      piece.inlinePresentationIntent = .stronglyEmphasized
      piece.foregroundColor = emphasis
    }
    result += piece
  }
  return Text(result)
}
