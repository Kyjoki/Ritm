import Foundation
import XCTest

@testable import RitmCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@MainActor
final class SecurityTests: XCTestCase {
  private let sessionJSON = #"{"authenticated":true,"requiresLogin":true}"#
  private func cookie(maxAge: Int) -> String {
    "__Host-ritm_session=header.payload.signature; Max-Age=\(maxAge); Path=/; HttpOnly; Secure; SameSite=Strict"
  }
  private func body(_ request: URLRequest) throws -> [String: Any] {
    let data = try XCTUnwrap(request.httpBody)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  func testLoginIdentifiesAsIOSDeviceAndOmitsEmptySecondFactor() async throws {
    let transport = StubTransport([
      StubReply(json: sessionJSON, headers: ["Set-Cookie": cookie(maxAge: 30 * 86_400)])
    ])
    let client = try APIClient(transport: transport)
    _ = try await client.login(
      login: "owner", password: "pw", deviceName: DeviceLabel.make(model: "iPhone14,5"))
    let firstRequest = await transport.requests().first
    let sent = try body(try XCTUnwrap(firstRequest))
    XCTAssertEqual(sent["client"] as? String, "ios")
    XCTAssertEqual(sent["deviceName"] as? String, "iPhone (iPhone14,5)")
    XCTAssertNil(sent["totp"])
    XCTAssertNil(sent["recoveryCode"])
    let saved = await client.sessionCredential()
    XCTAssertNotNil(saved, "a 30-day device cookie must be accepted")
  }

  func testLoginSendsTotpOrRecoveryCodeOnlyWhenGiven() async throws {
    let transport = StubTransport([
      StubReply(json: sessionJSON, headers: ["Set-Cookie": cookie(maxAge: 86_400)]),
      StubReply(json: sessionJSON, headers: ["Set-Cookie": cookie(maxAge: 86_400)]),
    ])
    let client = try APIClient(transport: transport)
    _ = try await client.login(login: "o", password: "p", totp: "123456")
    _ = try await client.login(login: "o", password: "p", recoveryCode: "abcd-efgh")
    let requests = await transport.requests()
    let first = try body(requests[0])
    let second = try body(requests[1])
    XCTAssertEqual(first["totp"] as? String, "123456")
    XCTAssertNil(first["recoveryCode"])
    XCTAssertEqual(second["recoveryCode"] as? String, "abcd-efgh")
    XCTAssertNil(second["totp"])
  }

  func testCookieLongerThanAbsoluteCapIsRejected() async throws {
    let client = try APIClient(
      transport: StubTransport([
        StubReply(json: sessionJSON, headers: ["Set-Cookie": cookie(maxAge: 180 * 86_400 + 1)])
      ]))
    do {
      _ = try await client.login(login: "o", password: "p")
      XCTFail("Cookie beyond 180 days accepted")
    } catch let error as APIError { XCTAssertEqual(error.code, "INVALID_SESSION") }
  }

  func testSecondFactorAndRateLimitErrors() async throws {
    let transport = StubTransport([
      StubReply(status: 401, json: #"{"error":"Нужен код","code":"TOTP_REQUIRED"}"#),
      StubReply(status: 401, json: #"{"error":"Неверный код","code":"TOTP_INVALID"}"#),
      StubReply(status: 429, json: #"{"error":"Много попыток","retryAfterSeconds":90}"#),
    ])
    let client = try APIClient(transport: transport)
    do {
      _ = try await client.login(login: "o", password: "p")
      XCTFail("expected TOTP_REQUIRED")
    } catch let error as APIError {
      XCTAssertTrue(error.requiresSecondFactor)
      XCTAssertFalse(error.requiresAuthentication)
    }
    do {
      _ = try await client.login(login: "o", password: "p", totp: "000000")
      XCTFail("expected TOTP_INVALID")
    } catch let error as APIError {
      XCTAssertTrue(error.isSecondFactorInvalid)
      XCTAssertEqual(error.message, "Неверный код")
    }
    do {
      _ = try await client.login(login: "o", password: "p", totp: "000000")
      XCTFail("expected 429")
    } catch let error as APIError {
      XCTAssertEqual(error.status, 429)
      XCTAssertEqual(error.retryAfterSeconds, 90)
    }
  }

  func testSecurityOverviewDecodesSessionsAndDates() async throws {
    let json = """
      {"totpEnabled":true,"recoveryCodesLeft":7,"sessions":[
        {"id":"s_1","client":"ios","deviceName":"iPhone (iPhone14,5)",
         "createdAt":"2026-10-01T10:00:00.000Z","lastSeenAt":"2026-11-01T08:30:00Z","current":true},
        {"id":"s_2","client":"web","deviceName":null,
         "createdAt":1790000000000,"lastSeenAt":1790000100,"current":false}]}
      """
    let client = try APIClient(transport: StubTransport([StubReply(json: json)]))
    let overview = try await client.security()
    XCTAssertTrue(overview.totpEnabled)
    XCTAssertEqual(overview.recoveryCodesLeft, 7)
    XCTAssertEqual(overview.sessions.count, 2)
    XCTAssertTrue(overview.sessions[0].current)
    XCTAssertNotNil(overview.sessions[0].createdAt)
    XCTAssertNotNil(overview.sessions[0].lastSeenAt)
    XCTAssertNil(overview.sessions[1].deviceName)
    XCTAssertEqual(overview.sessions[1].createdAt, Date(timeIntervalSince1970: 1_790_000_000))
    XCTAssertEqual(overview.sessions[1].lastSeenAt, Date(timeIntervalSince1970: 1_790_000_100))
    XCTAssertEqual(overview.otherSessions.map(\.id), ["s_2"])
  }

  func testOlderServerWithoutSecurityEndpointIsA404() async throws {
    let client = try APIClient(
      transport: StubTransport([StubReply(status: 404, json: #"{"error":"Not found"}"#)]))
    do {
      _ = try await client.security()
      XCTFail("expected 404")
    } catch let error as APIError { XCTAssertEqual(error.status, 404) }
  }

  func testRevokeUsesDeleteAndPostRoutesWithNoContentReply() async throws {
    let transport = StubTransport([
      StubReply(status: 204, json: ""), StubReply(status: 204, json: ""),
    ])
    let client = try APIClient(transport: transport)
    try await client.revokeSession(id: "s_2")
    try await client.revokeOtherSessions()
    let requests = await transport.requests()
    XCTAssertEqual(requests[0].httpMethod, "DELETE")
    XCTAssertEqual(requests[0].url?.path, "/api/security/sessions/s_2")
    XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
    XCTAssertEqual(requests[1].httpMethod, "POST")
    XCTAssertEqual(requests[1].url?.path, "/api/security/sessions/revoke-others")
  }

  func testRevokeRejectsIdsThatCouldEscapeThePath() async throws {
    let transport = StubTransport([])
    let client = try APIClient(transport: transport)
    for id in ["", "../logout", "a/b", "a b", "a?b"] {
      do {
        try await client.revokeSession(id: id)
        XCTFail("accepted \(id)")
      } catch let error as APIError { XCTAssertEqual(error.code, "INVALID_INPUT") }
    }
    let sent = await transport.requests()
    XCTAssertTrue(sent.isEmpty)
  }

  func testDeviceLabelHasNoPersonalNameAndIsBounded() {
    XCTAssertEqual(DeviceLabel.make(model: "iPhone14,5"), "iPhone (iPhone14,5)")
    XCTAssertEqual(DeviceLabel.make(model: nil), "iPhone")
    XCTAssertEqual(DeviceLabel.make(model: "  \n "), "iPhone")
    XCTAssertEqual(DeviceLabel.sanitized("a\u{0}b\nc"), "abc")
    XCTAssertEqual(DeviceLabel.sanitized(String(repeating: "x", count: 200))?.count, 60)
  }
}
