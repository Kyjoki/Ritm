import Foundation
import XCTest

@testable import RitmCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private actor HealthTransport: HTTPTransport {
  enum Outcome: Sendable {
    case reply(status: Int, body: String, responseURL: String?, contentType: String)
    case failure(URLError.Code)
  }

  private let outcome: Outcome
  private var recorded: [URLRequest] = []
  init(_ outcome: Outcome) { self.outcome = outcome }
  func requests() -> [URLRequest] { recorded }

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    recorded.append(request)
    switch outcome {
    case .failure(let code): throw URLError(code)
    case .reply(let status, let body, let responseURL, let contentType):
      let response = HTTPURLResponse(
        url: responseURL.flatMap(URL.init(string:)) ?? request.url!, statusCode: status,
        httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType])!
      return (Data(body.utf8), response)
    }
  }
}

final class ServerAddressTests: XCTestCase {
  private func address(_ raw: String) throws -> ServerAddress {
    try ServerAddress.validate(raw).get()
  }

  private func error(_ raw: String) -> ServerAddressError? {
    if case .failure(let error) = ServerAddress.validate(raw) { return error }
    return nil
  }

  func testDefaultIsProduction() {
    XCTAssertEqual(ServerAddress.production.origin, "https://ritm-eta-hazel.vercel.app")
    XCTAssertEqual(ServerAddress.production.account, "ritm-eta-hazel.vercel.app")
    XCTAssertEqual(APIClient.productionURL, ServerAddress.production.url)
  }

  func testNormalisesTrailingSlashCaseWhitespaceAndDefaultPort() throws {
    let expected = "https://laptop.tailnet.ts.net"
    for raw in [
      "https://laptop.tailnet.ts.net", "https://laptop.tailnet.ts.net/",
      "  HTTPS://Laptop.Tailnet.TS.net/  ", "laptop.tailnet.ts.net", "laptop.tailnet.ts.net/",
      "https://laptop.tailnet.ts.net:443", "https://laptop.tailnet.ts.net:443/",
    ] {
      XCTAssertEqual(try address(raw).origin, expected, raw)
      XCTAssertEqual(try address(raw).url.absoluteString, expected, raw)
    }
  }

  func testKeepsNonDefaultPortAndKeysAccountByHostAndPort() throws {
    let custom = try address("https://laptop.tailnet.ts.net:8443/")
    XCTAssertEqual(custom.port, 8443)
    XCTAssertEqual(custom.origin, "https://laptop.tailnet.ts.net:8443")
    XCTAssertEqual(custom.account, "laptop.tailnet.ts.net:8443")
    XCTAssertEqual(try address("laptop.tailnet.ts.net:8443"), custom)
    XCTAssertNotEqual(custom.account, try address("laptop.tailnet.ts.net").account)
    XCTAssertNotEqual(custom.account, ServerAddress.production.account)
  }

  func testRejectsEmpty() {
    for raw in ["", "   ", "\n"] { XCTAssertEqual(error(raw), .empty, raw) }
  }

  func testRejectsNonHTTPS() {
    for raw in ["http://laptop.tailnet.ts.net", "HTTP://x.example", "ftp://x.example", "ws://x.example"]
    {
      XCTAssertEqual(error(raw), .notHTTPS, raw)
    }
    XCTAssertEqual(error("://x.example"), .invalidHost)
  }

  func testRejectsCredentialsQueryFragmentAndPath() {
    XCTAssertEqual(error("https://owner:password@laptop.tailnet.ts.net"), .hasCredentials)
    XCTAssertEqual(error("https://owner@laptop.tailnet.ts.net"), .hasCredentials)
    XCTAssertEqual(error("https://laptop.tailnet.ts.net?x=1"), .hasQueryOrFragment)
    XCTAssertEqual(error("https://laptop.tailnet.ts.net/?x=1"), .hasQueryOrFragment)
    XCTAssertEqual(error("https://laptop.tailnet.ts.net#settings"), .hasQueryOrFragment)
    XCTAssertEqual(error("https://laptop.tailnet.ts.net/app"), .hasPath)
    XCTAssertEqual(error("https://laptop.tailnet.ts.net//"), .hasPath)
  }

  func testRejectsBadHosts() {
    for raw in [
      "https://", "https:///", "https://:8443", "https://.", "https://a..b", "https://-a.example",
      "https://a-.example", "https://exa mple.com", "https://example.com.", "https://[::1]",
      "https://[::1]:8443", "https://пример.рф", "https://exa_mple.com", "https://x.example\\evil",
    ] {
      XCTAssertEqual(error(raw), .invalidHost, raw)
    }
  }

  func testRejectsBadPorts() {
    for raw in [
      "https://x.example:", "https://x.example:0", "https://x.example:65536",
      "https://x.example:abc", "https://x.example:-1", "https://x.example:123456",
    ] {
      XCTAssertEqual(error(raw), .invalidPort, raw)
    }
    XCTAssertEqual(try? address("https://x.example:65535").port, 65535)
  }

  func testLookalikeHostsAreDistinctAddresses() throws {
    let real = try address("https://ritm-eta-hazel.vercel.app")
    XCTAssertEqual(real, ServerAddress.production)
    XCTAssertNotEqual(try address("https://ritm-eta-hazel.vercel.app.evil.example"), real)
    XCTAssertNotEqual(try address("https://ritm-eta-hazel.vercel.app:8443"), real)
  }

  func testMessagesAreRussianAndNeverEchoTheInput() {
    let secret = "owner:hunter2"
    guard case .failure(let failure) = ServerAddress.validate("https://\(secret)@x.example") else {
      return XCTFail("Credentials accepted")
    }
    XCTAssertEqual(failure, .hasCredentials)
    XCTAssertFalse(failure.localizedDescription.contains("hunter2"))
    XCTAssertNotNil(failure.errorDescription?.range(of: "[а-яА-Я]", options: .regularExpression))
  }

  // MARK: Health check

  func testHealthCheckSendsOnlyAnAnonymousGet() async throws {
    let transport = HealthTransport(
      .reply(status: 200, body: #"{"status":"ok"}"#, responseURL: nil, contentType: "application/json"))
    let target = try address("https://laptop.tailnet.ts.net:8443")
    try await target.checkHealth(using: transport)
    let requests = await transport.requests()
    XCTAssertEqual(requests.count, 1)
    XCTAssertEqual(requests[0].httpMethod, "GET")
    XCTAssertEqual(requests[0].url?.absoluteString, "https://laptop.tailnet.ts.net:8443/api/health")
    XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
    XCTAssertNil(requests[0].value(forHTTPHeaderField: "Origin"))
    XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
    XCTAssertNil(requests[0].httpBody)
    XCTAssertFalse(requests[0].httpShouldHandleCookies)
  }

  private func healthFailure(_ outcome: HealthTransport.Outcome) async throws -> APIError {
    let target = try address("https://laptop.tailnet.ts.net")
    do {
      try await target.checkHealth(using: HealthTransport(outcome))
    } catch let error as APIError { return error }
    XCTFail("Health check accepted")
    return APIError(message: "")
  }

  func testHealthCheckRejectsRedirectsOtherHostsAndForeignServers() async throws {
    let json = "application/json"
    var failure = try await healthFailure(
      .reply(status: 302, body: "{}", responseURL: nil, contentType: json))
    XCTAssertEqual(failure.code, "REDIRECT_BLOCKED")
    failure = try await healthFailure(
      .reply(
        status: 200, body: #"{"status":"ok"}"#, responseURL: "https://evil.example/api/health",
        contentType: json))
    XCTAssertEqual(failure.code, "REDIRECT_BLOCKED")
    failure = try await healthFailure(
      .reply(status: 404, body: "{}", responseURL: nil, contentType: json))
    XCTAssertEqual(failure.code, "NOT_RITM")
    failure = try await healthFailure(
      .reply(status: 200, body: "<html></html>", responseURL: nil, contentType: "text/html"))
    XCTAssertEqual(failure.code, "NOT_RITM")
    failure = try await healthFailure(
      .reply(status: 200, body: #"{"status":"down"}"#, responseURL: nil, contentType: json))
    XCTAssertEqual(failure.code, "NOT_RITM")
  }

  func testHealthCheckMapsConnectionFailuresToRussianMessages() async throws {
    let cases: [(URLError.Code, String)] = [
      (.serverCertificateUntrusted, "TLS"), (.secureConnectionFailed, "TLS"),
      (.cannotFindHost, "NETWORK"), (.timedOut, "NETWORK"), (.notConnectedToInternet, "NETWORK"),
    ]
    for (code, expected) in cases {
      let failure = try await healthFailure(.failure(code))
      XCTAssertEqual(failure.code, expected)
      XCTAssertNotNil(failure.message.range(of: "[а-яА-Я]", options: .regularExpression))
    }
  }
}
