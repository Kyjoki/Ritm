import Foundation
@_spi(RitmBuildTests) import XKit

/// Offline executable. No SigningContext, auth loader, device or real identity is used.
@main struct RitmSignerFixture {
  enum Failure: Error { case invalidFixture, assertion(String) }
  static func require(_ value: Bool, _ message: String) throws {
    guard value else { throw Failure.assertion(message) }
  }
  static func plist(_ data: Data) throws -> [String: Any] {
    guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else { throw Failure.invalidFixture }
    return result
  }
  private actor GroupSnapshots {
    let values: [[DeveloperServicesAppGroup]]
    private(set) var calls = 0
    init(_ values: [[DeveloperServicesAppGroup]]) { self.values = values }
    func next() -> [DeveloperServicesAppGroup] {
      defer { calls += 1 }
      return values[min(calls, values.count - 1)]
    }
  }
  static func checkGroupRecovery() async throws {
    func group(_ identifier: String) throws -> DeveloperServicesAppGroup {
      let data = try JSONSerialization.data(withJSONObject: [
        "applicationGroup": "synthetic-owned-record", "identifier": identifier, "name": "Fixture"
      ])
      return try JSONDecoder().decode(DeveloperServicesAppGroup.self, from: data)
    }
    let desired = DeveloperServicesAppGroup.GroupID(rawValue: "group.fixture.expected")
    let wanted = try group(desired.rawValue), other = try group("group.fixture.other")
    let delayed = GroupSnapshots([[], [other], [wanted]])
    let recovered = await DeveloperServicesAssignAppGroupsOperation.recoverExactOwnedGroup(desired) {
      await delayed.next()
    }
    try require(recovered?.groupID == desired, "must recover only the exact owned group")
    try require(await delayed.calls == 3, "bounded refresh must reach the delayed exact match")
    let absent = GroupSnapshots([[other]])
    let missing = await DeveloperServicesAssignAppGroupsOperation.recoverExactOwnedGroup(desired) {
      await absent.next()
    }
    try require(missing == nil, "must not borrow a different owned group")
    try require(await absent.calls == 3, "absent exact group must stop after three reads")
    let duplicate = GroupSnapshots([[wanted, wanted]])
    let ambiguous = await DeveloperServicesAssignAppGroupsOperation.recoverExactOwnedGroup(desired) {
      await duplicate.next()
    }
    try require(ambiguous == nil, "duplicate exact owned records must fail closed")
    try require(await duplicate.calls == 1, "ambiguous ownership must not retry creation")
  }
  static func main() async throws {
    guard CommandLine.arguments.count == 2 else { throw Failure.invalidFixture }
    let app = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let parent = app.deletingLastPathComponent()
    guard app.lastPathComponent == "Fixture.app",
      FileManager.default.fileExists(atPath: parent.appendingPathComponent("ritm-adhoc-fixture.json").path)
    else { throw Failure.invalidFixture }
    let extensionBundle = app.appendingPathComponent("PlugIns/FixtureWidget.appex", isDirectory: true)
    let rootData = try Data(contentsOf: parent.appendingPathComponent("root.entitlements"))
    let childData = try Data(contentsOf: parent.appendingPathComponent("extension.entitlements"))
    let rootValues = try plist(rootData), childValues = try plist(childData)
    try require(rootValues["application-identifier"] as? String == "RITMFIXTUR.app.ritm.signfixture",
      "fixture must use a synthetic root identity")
    try require(childValues["application-identifier"] as? String == "RITMFIXTUR.app.ritm.signfixture.Widget",
      "fixture must use a synthetic extension identity")
    let root = try PropertyListDecoder().decode(Entitlements.self, from: rootData)
    let child = try PropertyListDecoder().decode(Entitlements.self, from: childData)
    let signer = try Signer.first()
    let progress: @Sendable (Double?) -> Void = { _ in }
    try await signer.sign(app: app, identity: .adhoc,
      entitlementMapping: [app: root, extensionBundle: child], progress: progress)
    let a = try plist(await signer.analyze(executable: app.appendingPathComponent("Fixture")))
    let b = try plist(await signer.analyze(executable: extensionBundle.appendingPathComponent("FixtureWidget")))
    try require(a["application-identifier"] as? String == "RITMFIXTUR.app.ritm.signfixture", "root identifier")
    try require(b["application-identifier"] as? String == "RITMFIXTUR.app.ritm.signfixture.Widget", "extension identifier")
    try require(a["com.apple.developer.healthkit"] as? Bool == true, "root-only HealthKit retained")
    try require(b["com.apple.developer.healthkit"] == nil, "root-only HealthKit must not leak into extension")
    try require(a["keychain-access-groups"] as? [String] == ["RITMFIXTUR.app.ritm.signfixture"], "root keychain scope")
    try require(b["keychain-access-groups"] as? [String] == ["RITMFIXTUR.app.ritm.signfixture.Widget"], "extension keychain scope")
    for data in [a, b] {
      try require(data["com.apple.security.application-groups"] as? [String] == ["group.app.ritm.signfixture"], "shared fixture group")
    }
    var rejectedMissing = false
    do {
      try await signer.sign(app: app, identity: .adhoc, entitlementMapping: [app: root], progress: progress)
    } catch { rejectedMissing = true }
    try require(rejectedMissing, "missing extension scope must fail")
    var rejectedOutside = false
    do {
      let outside = parent.appendingPathComponent("Fixture.app-copy", isDirectory: true)
      try await signer.sign(app: app, identity: .adhoc,
        entitlementMapping: [app: root, outside: child], progress: progress)
    } catch { rejectedOutside = true }
    try require(rejectedOutside, "app sibling prefix must not match root")
    // Leave a valid final fixture after the negative checks.
    try await signer.sign(app: app, identity: .adhoc,
      entitlementMapping: [app: root, extensionBundle: child], progress: progress)
    try await checkGroupRecovery()
    let report: [String: Any] = [
      "kind": "offline-ad-hoc", "perBundleIdentifiers": true, "separateKeychainScopes": true,
      "rootOnlyEntitlementDidNotLeak": true, "missingChildRejected": true,
      "outsideRootRejected": true, "realDeveloperIdentityUsed": false,
      "appGroupRegistered": false, "deviceExecutionVerified": false,
      "exactOwnedGroupRecovery": true, "differentOwnedGroupRejected": true,
      "ownedGroupRefreshBounded": true,
    ]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      .write(to: parent.appendingPathComponent("signer-fixture-report.json"), options: .atomic)
    print("PASS: offline per-bundle ad-hoc fixture; no developer credentials or device used")
  }
}
