import Foundation
import XCTest

@testable import RitmCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct StubReply: Sendable {
  var status = 200
  var json: String
  var headers: [String: String] = [:]
  var responseURL: URL? = nil
}

actor StubTransport: HTTPTransport {
  private var replies: [StubReply]
  private var recorded: [URLRequest] = []
  init(_ replies: [StubReply]) { self.replies = replies }
  func requests() -> [URLRequest] { recorded }
  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    recorded.append(request)
    guard !replies.isEmpty else { throw URLError(.notConnectedToInternet) }
    let reply = replies.removeFirst()
    let headers = ["Content-Type": "application/json"].merging(reply.headers) { _, new in new }
    let response = HTTPURLResponse(
      url: reply.responseURL ?? request.url!, statusCode: reply.status,
      httpVersion: "HTTP/1.1", headerFields: headers)!
    return (Data(reply.json.utf8), response)
  }
}

/// Holds one request so session replacement can be exercised without wall-clock sleeps or networking.
private actor SuspendedTransport: HTTPTransport {
  private var pending: CheckedContinuation<(Data, HTTPURLResponse), any Error>?
  private var started: CheckedContinuation<Void, Never>?
  private var requestURL: URL?

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requestURL = request.url
    return try await withCheckedThrowingContinuation { continuation in
      pending = continuation
      started?.resume()
      started = nil
    }
  }

  func waitUntilRequested() async {
    if pending != nil { return }
    await withCheckedContinuation { started = $0 }
  }

  func releaseUnauthenticated() {
    guard let pending, let requestURL else { return }
    self.pending = nil
    let response = HTTPURLResponse(
      url: requestURL, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"])!
    pending.resume(
      returning: (Data(#"{"authenticated":false,"requiresLogin":true}"#.utf8), response))
  }
}

@MainActor
final class APIClientTests: XCTestCase {
  private let sessionJSON = #"{"authenticated":true,"requiresLogin":true}"#
  private let cookie =
    "__Host-ritm_session=header.payload.signature; Max-Age=28800; Path=/; HttpOnly; Secure; SameSite=Strict"
  private let taskID = "cfe09f74-c318-4bd4-a609-bbf545d0918f"

  private func credential() -> SessionCredential {
    SessionCredential(
      name: "__Host-ritm_session", value: "header.payload.signature",
      expires: Date().addingTimeInterval(3600))
  }

  func testRejectsUntrustedAndNonHTTPSOriginsBeforeAnyTransportCanReceiveCredentials() async {
    // The host is now configurable, so a different host is allowed; the origin must still be a
    // plain https origin with no credentials, path, query or fragment.
    let denied = [
      "http://ritm-eta-hazel.vercel.app", "http://laptop.tailnet.ts.net:8443",
      "https://ritm-eta-hazel.vercel.app:0", "https://owner:password@ritm-eta-hazel.vercel.app",
      "https://ritm-eta-hazel.vercel.app/path", "https://ritm-eta-hazel.vercel.app?forward=evil",
      "https://ritm-eta-hazel.vercel.app/#fragment", "ftp://evil.example",
    ]
    for raw in denied {
      guard let url = URL(string: raw) else { continue }
      XCTAssertThrowsError(try APIClient(baseURL: url, transport: StubTransport([]))) { error in
        XCTAssertEqual((error as? APIError)?.code, "INVALID_SERVER", raw)
      }
    }
  }

  func testConfiguredHostIsUsedForRequestsOriginAndRedirectRefusal() async throws {
    let base = URL(string: "https://laptop.tailnet.ts.net:8443")!
    let transport = StubTransport([
      StubReply(json: sessionJSON),
      StubReply(json: sessionJSON, responseURL: URL(string: "https://evil.example/api/session")),
      StubReply(json: sessionJSON, responseURL: APIClient.productionURL.appendingPathComponent("x")),
    ])
    let client = try APIClient(baseURL: base, transport: transport)
    XCTAssertEqual(client.baseURL.absoluteString, "https://laptop.tailnet.ts.net:8443")
    _ = try await client.session()
    for _ in 0..<2 {
      do {
        _ = try await client.session()
        XCTFail("Response from another host accepted")
      } catch let error as APIError { XCTAssertEqual(error.code, "REDIRECT_BLOCKED") }
    }
    let requests = await transport.requests()
    XCTAssertEqual(requests[0].url?.absoluteString, "https://laptop.tailnet.ts.net:8443/api/session")
    XCTAssertEqual(
      requests[0].value(forHTTPHeaderField: "Origin"), "https://laptop.tailnet.ts.net:8443")
  }

  func testLoginStoresOnlyValidatedPrivateCookieAndSendsExactOrigin() async throws {
    let transport = StubTransport([
      StubReply(json: sessionJSON, headers: ["Set-Cookie": cookie]),
      StubReply(json: sessionJSON),
    ])
    let client = try APIClient(transport: transport)
    await client.setLanguage(.en)
    let loggedIn = try await client.login(login: "owner", password: "test-only-password")
    XCTAssertTrue(loggedIn.authenticated)
    let saved = await client.sessionCredential()
    XCTAssertEqual(saved?.value, "header.payload.signature")
    _ = try await client.session()
    let requests = await transport.requests()
    XCTAssertEqual(requests.count, 2)
    XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
    XCTAssertEqual(
      requests[0].value(forHTTPHeaderField: "Origin"), APIClient.productionURL.absoluteString)
    XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
    XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Accept-Language"), "en")
    XCTAssertEqual(
      requests[1].value(forHTTPHeaderField: "Cookie"),
      "__Host-ritm_session=header.payload.signature")
    XCTAssertFalse(requests[1].httpShouldHandleCookies)
    XCTAssertEqual(requests[1].cachePolicy, .reloadIgnoringLocalCacheData)
    XCTAssertNil(requests[1].httpBody)
  }

  func testRejectsServerCookiesWithoutHostSecurityAttributes() async throws {
    let denied = [
      cookie.replacingOccurrences(of: "; Secure", with: ""),
      cookie.replacingOccurrences(of: "; HttpOnly", with: ""),
      cookie + "; Domain=ritm-eta-hazel.vercel.app",
      cookie.replacingOccurrences(of: "Path=/", with: "Path=/api"),
      cookie.replacingOccurrences(of: "SameSite=Strict", with: "SameSite=Lax"),
      cookie.replacingOccurrences(of: "Max-Age=28800", with: "Max-Age=15552001"),
    ]
    for value in denied {
      let client = try APIClient(
        transport: StubTransport([StubReply(json: sessionJSON, headers: ["Set-Cookie": value])]))
      do {
        _ = try await client.login(login: "owner", password: "test")
        XCTFail("Unsafe cookie accepted")
      } catch let error as APIError { XCTAssertEqual(error.code, "INVALID_SESSION") }
      let saved = await client.sessionCredential()
      XCTAssertNil(saved)
    }
  }

  func testRejectsExpiredOrHeaderInjectedRestoredCredentials() async throws {
    let transport = StubTransport([])
    let client = try APIClient(transport: transport)
    let denied = [
      SessionCredential(name: "other", value: "a.b.c", expires: Date().addingTimeInterval(60)),
      SessionCredential(
        name: "__Host-ritm_session", value: "a.b.c", expires: Date().addingTimeInterval(-1)),
      SessionCredential(
        name: "__Host-ritm_session", value: "a.b.c\r\nHost: evil.example",
        expires: Date().addingTimeInterval(60)),
      SessionCredential(
        name: "__Host-ritm_session", value: "a.b.c; other=secret",
        expires: Date().addingTimeInterval(60)),
      SessionCredential(name: "__Host-ritm_session", value: "a.b.c", expires: .distantFuture),
    ]
    for value in denied {
      do {
        try await client.restoreCredential(value)
        XCTFail("Invalid credential accepted")
      } catch let error as APIError { XCTAssertEqual(error.code, "INVALID_CREDENTIAL") }
    }
    let requests = await transport.requests()
    XCTAssertTrue(requests.isEmpty)
  }

  func testHabitConflictPreservesServerErrorAndExpectedVersionWithoutRetry() async throws {
    let transport = StubTransport([
      StubReply(status: 409, json: #"{"error":"Привычка изменена","code":"HABIT_CONFLICT"}"#)
    ])
    let client = try APIClient(transport: transport)
    try await client.restoreCredential(credential())
    do {
      _ = try await client.setHabitDay(
        id: taskID, date: "2026-10-28", completed: true, expectedUpdatedAt: "old-version")
      XCTFail("Expected conflict")
    } catch let error as APIError {
      XCTAssertTrue(error.isConflict)
      XCTAssertEqual(error.code, "HABIT_CONFLICT")
    }
    let requests = await transport.requests()
    XCTAssertEqual(requests.count, 1)
    let body = try XCTUnwrap(requests.first?.httpBody)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(object["expectedUpdatedAt"] as? String, "old-version")
    XCTAssertEqual(object["completed"] as? Bool, true)
  }

  func testTaskToggleUsesMinimalPatchWithoutInventedVersion() async throws {
    let task = RitmTask(id: taskID, title: "Дело", date: "2026-10-28", completed: true)
    let json = String(decoding: try JSONEncoder().encode(task), as: UTF8.self)
    let transport = StubTransport([StubReply(json: json)])
    let client = try APIClient(transport: transport)
    let result = try await client.setTaskCompleted(id: taskID, completed: true)
    XCTAssertTrue(result.completed)
    let requests = await transport.requests()
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
    XCTAssertEqual(Set(object.keys), ["completed"])
    XCTAssertEqual(requests[0].httpMethod, "PATCH")
  }

  func testAuthFailureClearsCookieAndRateLimitIsBounded() async throws {
    let transport = StubTransport([
      StubReply(status: 401, json: #"{"error":"Войдите","code":"AUTH_REQUIRED"}"#),
      StubReply(
        status: 429, json: #"{"error":"Лимит","code":"RATE_LIMIT","retryAfterSeconds":20}"#),
      StubReply(
        status: 429, json: #"{"error":"Лимит","code":"RATE_LIMIT","retryAfterSeconds":99999}"#),
    ])
    let client = try APIClient(transport: transport)
    try await client.restoreCredential(credential())
    do {
      _ = try await client.bootstrap()
      XCTFail("Expected auth error")
    } catch let error as APIError { XCTAssertTrue(error.requiresAuthentication) }
    let cleared = await client.sessionCredential()
    XCTAssertNil(cleared)
    do {
      _ = try await client.session()
      XCTFail("Expected rate limit")
    } catch let error as APIError { XCTAssertEqual(error.retryAfterSeconds, 20) }
    do {
      _ = try await client.session()
      XCTFail("Expected rate limit")
    } catch let error as APIError { XCTAssertNil(error.retryAfterSeconds) }
  }

  func testLogoutClearsLocalSessionEvenWhenOffline() async throws {
    let client = try APIClient(transport: StubTransport([]))
    try await client.restoreCredential(credential())
    do {
      try await client.logout()
      XCTFail("Expected network failure")
    } catch let error as APIError { XCTAssertEqual(error.code, "NETWORK") }
    let cleared = await client.sessionCredential()
    XCTAssertNil(cleared)
  }

  func testOldSessionResponseCannotClearRestoredCredential() async throws {
    let transport = SuspendedTransport()
    let client = try APIClient(transport: transport)
    let pending = Task { try await client.session() }
    await transport.waitUntilRequested()
    let replacement = credential()
    try await client.restoreCredential(replacement)
    await transport.releaseUnauthenticated()
    do {
      _ = try await pending.value
      XCTFail("Old session response should be cancelled")
    } catch is CancellationError {}
    let retained = await client.sessionCredential()
    XCTAssertEqual(retained, replacement)
  }

  func testSlowLogoutCannotEraseNewlyRestoredCredential() async throws {
    let transport = SuspendedTransport()
    let client = try APIClient(transport: transport)
    try await client.restoreCredential(credential())
    let pending = Task { try await client.logout() }
    await transport.waitUntilRequested()
    let replacement = SessionCredential(
      name: "__Host-ritm_session", value: "new.payload.signature",
      expires: Date().addingTimeInterval(3600))
    try await client.restoreCredential(replacement)
    await transport.releaseUnauthenticated()
    do {
      try await pending.value
      XCTFail("Old logout response should be cancelled")
    } catch is CancellationError {}
    let retained = await client.sessionCredential()
    XCTAssertEqual(retained, replacement)
  }

  func testRedirectResponseDoesNotInstallCookiesAndDoesNotRetry() async throws {
    let transport = StubTransport([
      StubReply(
        status: 302, json: "{}",
        headers: [
          "Location": "https://evil.example/collect", "Set-Cookie": cookie,
        ])
    ])
    let client = try APIClient(transport: transport)
    do {
      _ = try await client.login(login: "owner", password: "test")
      XCTFail("Redirect accepted")
    } catch let error as APIError { XCTAssertEqual(error.code, "REDIRECT_BLOCKED") }
    let saved = await client.sessionCredential()
    let requests = await transport.requests()
    XCTAssertNil(saved)
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(requests[0].url?.host, APIClient.productionURL.host)
  }

  func testDelegateRefusesToForwardRequestIncludingCrossOriginLoginBody() async throws {
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    let original = URLRequest(url: APIClient.productionURL.appendingPathComponent("api/login"))
    let task = session.dataTask(with: original)  // Not resumed: no network access.
    let redirect = HTTPURLResponse(
      url: original.url!, statusCode: 307, httpVersion: nil, headerFields: nil)!
    var forwarded = URLRequest(url: URL(string: "https://evil.example/collect")!)
    forwarded.httpBody = Data("private body".utf8)
    forwarded.setValue("__Host-ritm_session=private", forHTTPHeaderField: "Cookie")
    let result: URLRequest? = await withCheckedContinuation { continuation in
      RejectRedirects().urlSession(
        session, task: task, willPerformHTTPRedirection: redirect,
        newRequest: forwarded
      ) { continuation.resume(returning: $0) }
    }
    XCTAssertNil(result)
  }

  func testGoogleReadOnlyQueryCarriesOwnerTimeZoneWithoutPathEscape() async throws {
    let json =
      #"{"events":[],"from":"2026-10-28","to":"2026-10-29","timeZone":"Asia/Qyzylorda","fetchedAt":"2026-10-28T08:00:00Z","partial":false}"#
    let transport = StubTransport([StubReply(json: json)])
    let client = try APIClient(transport: transport)
    _ = try await client.googleEvents(
      from: "2026-10-28", to: "2026-10-29", timeZone: "Asia/Qyzylorda")
    let requests = await transport.requests()
    XCTAssertEqual(requests[0].httpMethod, "GET")
    XCTAssertEqual(requests[0].url?.path, "/api/integrations/google/events")
    let items = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems
    XCTAssertEqual(items?.first(where: { $0.name == "timeZone" })?.value, "Asia/Qyzylorda")
  }

  func testFinanceWriteCarriesSnapshotVersionAndDoesNotMixUnionFields() async throws {
    let entry = FinanceEntry(
      id: taskID,
      input: .init(
        type: .expense, amountMinor: 100,
        date: "2026-10-29", category: "Food"), createdAt: "created", updatedAt: "new-version")
    let data = try JSONEncoder().encode(entry)
    let transport = StubTransport([
      StubReply(json: "{\"entry\":\(String(decoding: data, as: UTF8.self))}")
    ])
    let client = try APIClient(transport: transport)
    let result = try await client.updateFinanceEntry(
      id: taskID, entry: entry.input, expectedUpdatedAt: "previous-version")
    XCTAssertEqual(result.updatedAt, "new-version")
    let requests = await transport.requests()
    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
    XCTAssertEqual(body["expectedUpdatedAt"] as? String, "previous-version")
    let payload = try XCTUnwrap(body["entry"] as? [String: Any])
    XCTAssertEqual(payload["amountMinor"] as? Int, 100)
    XCTAssertNil(payload["id"])
    XCTAssertNil(payload["asOf"])
  }

  func testGoogleTaskCompletionRequiresActualProviderProof() async throws {
    let event = GoogleCalendarEvent(
      id: "google_event_id", title: "Task", etag: "\"event-version\"",
      start: .init(date: "2026-10-29"), end: .init(date: "2026-10-30"), timeZone: "Asia/Qyzylorda",
      allDay: true)
    let transport = StubTransport([])
    let client = try APIClient(transport: transport)
    do {
      _ = try await client.completeGoogleTask(event: event, completed: true)
      XCTFail("Missing task proof accepted")
    } catch let error as APIError { XCTAssertEqual(error.code, "GOOGLE_TASKS_REQUIRED") }
    let requests = await transport.requests()
    XCTAssertTrue(requests.isEmpty)
  }

  func testGoogleTaskWriteIncludesBothEtagsAndConnectionIdentity() async throws {
    let event = GoogleCalendarEvent(
      id: "google_event_id", title: "Task", etag: "\"event-version\"",
      start: .init(date: "2026-10-29"), end: .init(date: "2026-10-30"), timeZone: "Asia/Qyzylorda",
      allDay: true,
      googleTask: GoogleTaskCompletion(
        taskListId: "list", id: "google-task", etag: "\"task-version\"",
        status: "completed", connectionId: String(repeating: "a", count: 64)))
    let data = try JSONEncoder().encode(event)
    let transport = StubTransport([
      StubReply(json: "{\"event\":\(String(decoding: data, as: UTF8.self))}")
    ])
    let client = try APIClient(transport: transport)
    _ = try await client.completeGoogleTask(event: event, completed: true)
    let requests = await transport.requests()
    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
    XCTAssertEqual(body["etag"] as? String, "\"event-version\"")
    XCTAssertEqual(body["taskEtag"] as? String, "\"task-version\"")
    XCTAssertEqual(body["connectionId"] as? String, String(repeating: "a", count: 64))
    XCTAssertEqual(requests[0].url?.path, "/api/integrations/google/events/google_event_id/task")
  }

  func testGoogleCreatePreservesIdempotencyKeyAndRejectsPathInjection() async throws {
    let event = GoogleCalendarEvent(
      id: "google_event_id", title: "Meeting",
      start: .init(date: "2026-10-29"), end: .init(date: "2026-10-30"), timeZone: "Asia/Qyzylorda",
      allDay: true)
    let transport = StubTransport([
      StubReply(json: String(decoding: try JSONEncoder().encode(event), as: UTF8.self))
    ])
    let client = try APIClient(transport: transport)
    _ = try await client.createGoogleEvent(
      event: GoogleEventInput(title: "Meeting", date: "2026-10-29", allDay: true), requestId: taskID
    )
    do {
      try await client.deleteGoogleEvent(id: "../settings/openai", etag: "version")
      XCTFail("Path injection accepted")
    } catch let error as APIError { XCTAssertEqual(error.code, "INVALID_INPUT") }
    let requests = await transport.requests()
    XCTAssertEqual(requests.count, 1)
    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
    XCTAssertEqual(body["requestId"] as? String, taskID)
  }

  func testChatUsesLongTimeoutAndPreservesReviewContext() async throws {
    let conversation = Conversation(id: taskID, title: "Review")
    let transport = StubTransport([
      StubReply(json: String(decoding: try JSONEncoder().encode(conversation), as: UTF8.self))
    ])
    let client = try APIClient(transport: transport)
    _ = try await client.chat(
      conversationId: taskID, message: "New evidence", requestId: taskID, mode: .ideaReview,
      reviewMessageId: taskID)
    let requests = await transport.requests()
    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
    XCTAssertEqual(body["mode"] as? String, "idea_review")
    XCTAssertEqual(body["reviewMessageId"] as? String, taskID)
    XCTAssertEqual(body["requestId"] as? String, taskID)
    XCTAssertEqual(requests[0].timeoutInterval, 120)
  }

  func testProposalsAreNeverAppliedByReadingAndRequireExplicitSelectedIDs() async throws {
    let conversation = Conversation(id: taskID, title: "Plan")
    let response = ProposalResult(tasks: [], conversation: conversation)
    let transport = StubTransport([
      StubReply(json: String(decoding: try JSONEncoder().encode(response), as: UTF8.self))
    ])
    let client = try APIClient(transport: transport)
    do {
      _ = try await client.proposals(
        action: .apply, conversationId: taskID, messageId: taskID, proposalIds: [])
      XCTFail("Empty selection accepted")
    } catch let error as APIError { XCTAssertEqual(error.code, "INVALID_INPUT") }
    _ = try await client.proposals(
      action: .apply, conversationId: taskID, messageId: taskID, proposalIds: [taskID])
    let requests = await transport.requests()
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(requests[0].url?.path, "/api/proposals/apply")
    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
    XCTAssertEqual(body["proposalIds"] as? [String], [taskID])
  }

  func testDeleteRequiresPositiveServerAcknowledgment() async throws {
    let client = try APIClient(transport: StubTransport([StubReply(json: #"{"deleted":false}"#)]))
    do {
      try await client.deleteHabit(id: taskID, expectedUpdatedAt: "version")
      XCTFail("False deletion treated as success")
    } catch let error as APIError { XCTAssertEqual(error.code, "INVALID_RESPONSE") }
  }

  func testInvalidFinancePayloadIsKnownUnsentInsteadOfUncertainNetworkFailure() async throws {
    let transport = StubTransport([])
    let client = try APIClient(transport: transport)
    do {
      _ = try await client.createFinanceEntry(FinanceEntryInput(type: .transfer))
      XCTFail("Incomplete transfer accepted")
    } catch let error as APIError {
      XCTAssertEqual(error.status, 400)
      XCTAssertEqual(error.code, "INVALID_INPUT")
    }
    let requests = await transport.requests()
    XCTAssertTrue(requests.isEmpty)
  }
}
