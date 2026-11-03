// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Allows Foundation/API tests on Linux/Windows without trying to compile SwiftUI.
// xtool builds the default library product for the iPhone SDK.
let coreTestsOnly = ProcessInfo.processInfo.environment["RITM_CORE_TESTS_ONLY"] == "1"
var targets: [Target] = [
  .target(name: "RitmCore"),
  .testTarget(name: "RitmCoreTests", dependencies: ["RitmCore"]),
]
if !coreTestsOnly {
  // Fonts holds Inter, the web app's typeface, registered at launch by RitmFonts.
  targets.append(.target(name: "Ritm", dependencies: ["RitmCore"], resources: [.copy("Fonts")]))
}

let package = Package(
  name: "Ritm",
  platforms: [.iOS("27.0")],
  products: coreTestsOnly ? [] : [.library(name: "Ritm", targets: ["Ritm"])],
  targets: targets
)
