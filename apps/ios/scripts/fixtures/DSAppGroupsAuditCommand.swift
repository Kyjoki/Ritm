import ArgumentParser
import Dependencies
import Foundation
import XKit

/// Authenticated read only: outputs counts, never identifiers or credentials.
struct DSAppGroupsAuditCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "app-groups-audit", abstract: "Read owned App Group counts for Ritm without printing identifiers")

  func run() async throws {
    do {
      @Dependency(\.keyValueStorage) var storage
      guard let data = try storage.data(forKey: "XTLAuthToken") else {
        throw Console.Error("Saved Xcode authentication is required.")
      }
      // Avoid AuthToken.saved(), whose provider-mismatch path can clear storage.
      let token = try JSONDecoder().decode(AuthToken.self, from: data)
      let auth = token.authData()
      guard case .xcode(let xcode) = auth else {
        throw Console.Error("Xcode authentication is required for this read-only list.")
      }
      let groups = try await DeveloperServicesClient(authData: xcode).send(
        DeveloperServicesListAppGroupsRequest(platform: .iOS, teamID: xcode.teamID))
      let base = "app.ritm.personal"
      let namespace = "XTL-" + auth.identityID.split(separator: "-")[0].uppercased()
      let expected = "group." + namespace + "." + base
      func logical(_ value: String) -> String {
        let body = value.hasPrefix("group.") ? String(value.dropFirst(6)) : value
        return body.hasPrefix("XTL-") ? body.split(separator: ".").dropFirst().joined(separator: ".") : body
      }
      let result: [String: Any] = [
        "ownedGroupsCount": groups.count,
        "exactExpectedMatches": groups.filter { $0.groupID.rawValue == expected }.count,
        "logicalBaseMatches": groups.filter { logical($0.groupID.rawValue) == base }.count,
        "readOnly": true,
      ]
      let output = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
      print(String(decoding: output, as: UTF8.self))
    } catch {
      // No server reason, auth record, team ID or group ID reaches the console.
      throw Console.Error("Read-only App Group list failed; credential and identifier details are redacted.")
    }
  }
}
