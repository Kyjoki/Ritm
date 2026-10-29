import Foundation
import RitmCore
import SwiftUI

enum CalendarPalette {
  /// The colour an entry is drawn with (src/lib/calendar-colors.ts): Ritm's soft swatches for
  /// Google IDs, a custom colour as is, otherwise the accent.
  static func entryColor(_ id: String?) -> Color {
    guard let hex = CalendarPlan.entryHex(id), let value = UInt32(hex, radix: 16) else {
      return RitmTheme.accentColor
    }
    return Color(rgb: value)
  }
  /// `--calendar-event-bg` and `--calendar-event-border`.
  static func entryFill(_ id: String?) -> Color {
    RitmTheme.mix(entryColor(id), 0.24, into: RitmTheme.panel)
  }
  static func entryBorder(_ id: String?) -> Color {
    RitmTheme.mix(entryColor(id), 0.76, into: RitmTheme.panel)
  }

  static let values: [(String, String)] = [
    ("#b71c50", "b71c50"), ("#e91e63", "e91e63"), ("4", "e67c73"), ("11", "d50000"),
    ("6", "f4511e"), ("#ef6c00", "ef6c00"), ("#f09300", "f09300"), ("5", "f6bf26"),
    ("#e4c441", "e4c441"), ("#c0ca33", "c0ca33"), ("#7cb342", "7cb342"), ("10", "0b8043"),
    ("2", "33b679"), ("#009688", "009688"), ("7", "039be5"), ("#4285f4", "4285f4"),
    ("1", "7986cb"), ("9", "3f51b5"), ("#b39ddb", "b39ddb"), ("#9e69af", "9e69af"),
    ("3", "8e24aa"), ("#795548", "795548"), ("8", "616161"), ("#a79b8e", "a79b8e"),
  ]
  static func color(_ id: String?) -> Color {
    let custom =
      id?.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil
      ? String(id!.dropFirst()) : nil
    guard let hex = values.first(where: { $0.0 == id })?.1 ?? custom,
      let value = UInt64(hex, radix: 16)
    else { return RitmTheme.lavender }
    return Color(
      red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
      blue: Double(value & 255) / 255)
  }
}

struct CalendarColorPicker: View {
  @Environment(RitmStore.self) private var store
  @Binding var colorID: String
  var extended = true
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button(store.text("Цвет по умолчанию", "Default color")) { colorID = "" }.frame(minHeight: 44)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 56), spacing: 8)], spacing: 8) {
        ForEach(CalendarPalette.values.filter { extended || !$0.0.hasPrefix("#") }, id: \.0) {
          item in
          Button {
            colorID = item.0
          } label: {
            Circle().fill(CalendarPalette.color(item.0)).frame(width: 30, height: 30)
              .overlay {
                if colorID == item.0 {
                  Image(systemName: "checkmark").foregroundStyle(.white).shadow(radius: 1)
                }
              }
              .frame(minWidth: 44, minHeight: 44)
          }.buttonStyle(RitmPressStyle())
            .accessibilityLabel(store.text("Цвет ", "Color ") + item.0)
            .accessibilityAddTraits(colorID == item.0 ? .isSelected : [])
        }
      }
      if !extended {
        Text(
          store.text(
            "Дополнительные оттенки включаются в настройках Google.",
            "Enable extra colors in Google settings.")
        ).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}
