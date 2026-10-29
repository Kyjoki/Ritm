import CoreText
import Foundation
import SwiftUI

/// Inter 4.1 (SIL Open Font License, Fonts/Inter-OFL.txt), the typeface of the web app
/// (@fontsource/inter). Four static weights cover every web weight; a weight of 650 renders bold.
enum RitmFonts {
  /// Registers the bundled faces for this process. If that fails, text falls back to the system
  /// font instead of disappearing.
  static func register() {
    guard
      let folder = Bundle.module.url(forResource: "Fonts", withExtension: nil),
      let files = try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil)
    else { return }
    for file in files where file.pathExtension == "ttf" {
      CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
    }
  }

  static func name(_ weight: Font.Weight) -> String {
    if weight == .bold || weight == .heavy || weight == .black { return "Inter-Bold" }
    if weight == .semibold { return "Inter-SemiBold" }
    if weight == .medium { return "Inter-Medium" }
    return "Inter-Regular"
  }
}
