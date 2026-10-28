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
  targets.append(.target(name: "Ritm", dependencies: ["RitmCore"]))
}

let package = Package(
  name: "Ritm",
  platforms: [.iOS(.v17)],
  products: coreTestsOnly ? [] : [.library(name: "Ritm", targets: ["Ritm"])],
  targets: targets
)
