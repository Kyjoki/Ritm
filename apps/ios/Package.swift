// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Allows Foundation/API tests on Linux/Windows without trying to compile SwiftUI.
// xtool builds the default library product for the iPhone SDK.
let coreTestsOnly = ProcessInfo.processInfo.environment["RITM_CORE_TESTS_ONLY"] == "1"
let interactive = ProcessInfo.processInfo.environment["RITM_INTERACTIVE"] == "1"
let systemSettings: [SwiftSetting] = interactive ? [.define("RITM_INTERACTIVE")] : []
var targets: [Target] = [
  .target(name: "RitmCore", swiftSettings: systemSettings),
  .target(name: "RitmSystem", dependencies: ["RitmCore"], swiftSettings: systemSettings),
  .testTarget(name: "RitmCoreTests", dependencies: ["RitmCore", "RitmSystem"], swiftSettings: systemSettings),
]
if !coreTestsOnly {
  // Fonts holds Inter, the web app's typeface, registered at launch by RitmFonts.
  targets.append(.target(name: "Ritm", dependencies: ["RitmCore", "RitmSystem"],
    resources: [.copy("Fonts")], swiftSettings: systemSettings))
  targets.append(.target(name: "RitmWidgets", dependencies: ["RitmCore", "RitmSystem"],
    path: "LiveActivity", exclude: ["RitmWidget-Info.plist", "RitmWidget.entitlements", "LIVE_ACTIVITY.md"],
    swiftSettings: systemSettings,
    // xtool 1.24.0 otherwise strips WidgetBundle.main. This is local to the extension;
    // the installed tool is unchanged. See xtool PR #393 and SYSTEM_FEATURES_BUILD.md.
    linkerSettings: [.unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_main"])]))
}

let package = Package(
  name: "Ritm",
  platforms: [.iOS("27.0")],
  products: coreTestsOnly ? [] : [
    .library(name: "Ritm", targets: ["Ritm"]),
    .library(name: "RitmWidgets", targets: ["RitmWidgets"]),
  ],
  targets: targets
)
