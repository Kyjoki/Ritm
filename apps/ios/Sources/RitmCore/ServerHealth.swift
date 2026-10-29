import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

extension ServerAddress {
  private static let maxHealthBody = 1024

  /// Unauthenticated `GET /api/health` (the server answers `{"status":"ok"}` without touching its
  /// database). No cookie, no Origin, no redirect is followed, and nothing from the response is kept.
  public func checkHealth() async throws {
    try await checkHealth(using: EphemeralTransport())
  }

  func checkHealth(using transport: any HTTPTransport) async throws {
    var request = URLRequest(
      url: url.appendingPathComponent("api/health"),
      cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
    request.httpMethod = "GET"
    request.httpShouldHandleCookies = false
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    let data: Data
    let response: HTTPURLResponse
    do {
      (data, response) = try await transport.send(request)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError {
      if error.code == .cancelled { throw CancellationError() }
      throw Self.connectionError(error.code)
    } catch let error as APIError {
      throw error
    } catch {
      throw Self.healthError("Не удалось связаться с сервером.", code: "NETWORK")
    }
    if (300...399).contains(response.statusCode) {
      throw Self.healthError(
        "Сервер перенаправляет на другой адрес. Укажите конечный адрес без перенаправления.",
        status: response.statusCode, code: "REDIRECT_BLOCKED")
    }
    guard let responseURL = response.url, responseURL.scheme == "https",
      responseURL.host?.lowercased() == host, (responseURL.port ?? 443) == (port ?? 443)
    else {
      throw Self.healthError("Перенаправление заблокировано.", code: "REDIRECT_BLOCKED")
    }
    guard response.statusCode == 200 else {
      throw Self.healthError(
        "Сервер ответил кодом \(response.statusCode). Похоже, это не Ritm или он не запущен.",
        status: response.statusCode, code: "NOT_RITM")
    }
    guard data.count <= Self.maxHealthBody,
      response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("application/json")
        == true,
      let body = try? JSONDecoder().decode(HealthBody.self, from: data), body.status == "ok"
    else {
      throw Self.healthError("По этому адресу отвечает не сервер Ritm.", code: "NOT_RITM")
    }
  }

  private static func connectionError(_ code: URLError.Code) -> APIError {
    switch code {
    case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
      .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
      return healthError(
        "Не удалось установить защищённое соединение: у сервера нет доверенного HTTPS-сертификата.",
        code: "TLS")
    case .cannotFindHost, .dnsLookupFailed:
      return healthError(
        "Сервер с таким именем не найден. Проверьте адрес и что Tailscale включён на iPhone.",
        code: "NETWORK")
    case .timedOut:
      return healthError(
        "Сервер не ответил вовремя. Проверьте, что он запущен, а Tailscale включён.",
        code: "NETWORK")
    default:
      return healthError(
        "Не удалось связаться с сервером. Проверьте адрес, подключение и что сервер запущен.",
        code: "NETWORK")
    }
  }

  private static func healthError(_ message: String, status: Int = 0, code: String) -> APIError {
    APIError(message: message, status: status, code: code)
  }
}

private struct HealthBody: Decodable { let status: String }
