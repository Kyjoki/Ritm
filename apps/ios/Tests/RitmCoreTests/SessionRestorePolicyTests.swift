import Foundation
import XCTest

@testable import RitmCore

final class SessionRestorePolicyTests: XCTestCase {
  func testServerErrorAtLaunchKeepsSavedSession() {
    let failure = APIError(message: "server", status: 500, code: "SERVER_ERROR")
    XCTAssertTrue(SessionRestorePolicy.keepsSignedIn(afterStartupFailure: failure, hadSavedSession: true))
  }

  func testLostConnectionAtLaunchKeepsSavedSession() {
    XCTAssertTrue(
      SessionRestorePolicy.keepsSignedIn(
        afterStartupFailure: URLError(.notConnectedToInternet), hadSavedSession: true))
    let network = APIError(message: "offline", code: "NETWORK")
    XCTAssertTrue(SessionRestorePolicy.keepsSignedIn(afterStartupFailure: network, hadSavedSession: true))
  }

  func testRateLimitAtLaunchKeepsSavedSession() {
    let failure = APIError(message: "slow down", status: 429, code: "RATE_LIMIT", retryAfterSeconds: 5)
    XCTAssertTrue(SessionRestorePolicy.keepsSignedIn(afterStartupFailure: failure, hadSavedSession: true))
  }

  func testRevokedSessionSignsOut() {
    let failure = APIError(message: "sign in", status: 401, code: "AUTH_REQUIRED")
    XCTAssertFalse(SessionRestorePolicy.keepsSignedIn(afterStartupFailure: failure, hadSavedSession: true))
  }

  func testNoSavedSessionNeverPretendsToBeSignedIn() {
    let failure = APIError(message: "server", status: 500, code: "SERVER_ERROR")
    XCTAssertFalse(SessionRestorePolicy.keepsSignedIn(afterStartupFailure: failure, hadSavedSession: false))
  }
}
