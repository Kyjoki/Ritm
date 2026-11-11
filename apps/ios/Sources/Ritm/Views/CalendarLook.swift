import RitmCore
import SwiftUI

// What the redesigned calendar shares between its pieces: the 24/12-hour setting, the saturated
// block colours with their ink, and the slide between two periods.

private struct CalendarHourFormatKey: EnvironmentKey {
  static let defaultValue = CalendarHourFormat.default
}

extension EnvironmentValues {
  /// 24-hour by default; the side menu switches it and the choice is remembered.
  var calendarHourFormat: CalendarHourFormat {
    get { self[CalendarHourFormatKey.self] }
    set { self[CalendarHourFormatKey.self] = newValue }
  }
}

extension CalendarPalette {
  /// The full-strength colour a solid block is filled with.
  static func solid(_ id: String?) -> Color {
    guard let hex = CalendarPlan.solidHex(id), let value = UInt32(hex, radix: 16) else {
      return RitmTheme.accentColor
    }
    return Color(rgb: value)
  }

  /// White on the saturated colours, a dark ink on the yellows and limes, the accent's own ink
  /// on the accent.
  static func ink(_ id: String?) -> Color {
    guard let hex = CalendarPlan.solidHex(id) else { return RitmTheme.accentInk }
    return CalendarPlan.prefersDarkInk(hex: hex) ? Color(rgb: 0x1B1626) : .white
  }
}

/// The slide of a period change: the current period leaves to one side, the next one comes in
/// from the other, both on the project easing. Reduce Motion changes the period at once.
enum CalendarSlide {
  @MainActor
  static func run(
    direction: Int, width: CGFloat, reduceMotion: Bool, offset: Binding<CGFloat>,
    step: @MainActor () -> Void
  ) async {
    guard !reduceMotion else {
      step()
      offset.wrappedValue = 0
      return
    }
    withAnimation(RitmMotion.easeOut(0.16)) { offset.wrappedValue = CGFloat(-direction) * width }
    try? await Task.sleep(for: .milliseconds(160))
    step()
    var instant = Transaction()
    instant.disablesAnimations = true
    withTransaction(instant) { offset.wrappedValue = CGFloat(direction) * width }
    await Task.yield()
    withAnimation(RitmMotion.ease(0.3)) { offset.wrappedValue = 0 }
  }
}
