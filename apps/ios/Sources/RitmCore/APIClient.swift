import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct APIError: Error, Sendable, Equatable, LocalizedError {
  public let message: String
  public let status: Int
  public let code: String?
  public let retryAfterSeconds: Int?
  public var errorDescription: String? { message }
  public var isConflict: Bool { status == 409 }
  public var requiresAuthentication: Bool { status == 401 && code == "AUTH_REQUIRED" }

  public init(message: String, status: Int = 0, code: String? = nil, retryAfterSeconds: Int? = nil)
  {
    self.message = message
    self.status = status
    self.code = code
    self.retryAfterSeconds = retryAfterSeconds
  }
}

/// Store this in Keychain, never UserDefaults, logs, files, analytics or a shared cookie jar.
/// The password is deliberately not part of the persisted credential.
public struct SessionCredential: Codable, Sendable, Equatable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public let name: String
  public let value: String
  public let expires: Date
  public var description: String { "SessionCredential(<redacted>)" }
  public var debugDescription: String { description }

  public init(name: String, value: String, expires: Date) {
    self.name = name
    self.value = value
    self.expires = expires
  }
}

/// Internal injection is for deterministic tests; the app cannot supply arbitrary transport/hosts.
protocol HTTPTransport: Sendable {
  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession is thread-safe. Configuration and delegate never mutate after initialization.
final class EphemeralTransport: HTTPTransport, @unchecked Sendable {
  private let session: URLSession
  private let redirectDelegate: RejectRedirects

  init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 180
    let delegate = RejectRedirects()
    redirectDelegate = delegate
    session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
  }

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw APIError(message: "Сервер вернул некорректный ответ.", code: "INVALID_RESPONSE")
    }
    return (data, response)
  }

  deinit { session.invalidateAndCancel() }
}

/// API routes must reply directly. Refusing even same-origin redirects also prevents a later
/// redirect in a chain from forwarding the manually attached owner session or a login body.
final class RejectRedirects: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

public actor APIClient {
  public static let productionURL = URL(string: "https://ritm-eta-hazel.vercel.app")!
  private static let cookieName = "__Host-ritm_session"
  private static let sessionLifetime: TimeInterval = 8 * 60 * 60
  public nonisolated let baseURL: URL
  private let transport: any HTTPTransport
  private var credential: SessionCredential?
  private var generation: UInt64 = 0
  private var language: Language = .ru

  public init(baseURL: URL = APIClient.productionURL) throws {
    self.baseURL = try Self.validatedBaseURL(baseURL)
    self.transport = EphemeralTransport()
  }

  init(baseURL: URL = APIClient.productionURL, transport: any HTTPTransport) throws {
    self.baseURL = try Self.validatedBaseURL(baseURL)
    self.transport = transport
  }

  static func validatedBaseURL(_ url: URL) throws -> URL {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.scheme == "https", components.host == productionURL.host,
      components.port == nil || components.port == 443,
      components.user == nil, components.password == nil,
      components.query == nil, components.fragment == nil,
      components.path.isEmpty || components.path == "/"
    else {
      throw APIError(message: "Разрешён только защищённый адрес Ritm.", code: "INVALID_SERVER")
    }
    return productionURL
  }

  public func setLanguage(_ language: Language) { self.language = language }

  public func sessionCredential() -> SessionCredential? {
    if let credential, credential.expires <= Date() { clearCredential() }
    return credential
  }

  public func restoreCredential(_ saved: SessionCredential) throws {
    clearCredential()
    guard Self.isValidCredential(saved, now: Date()) else {
      throw APIError(message: "Сессия истекла. Войдите снова.", code: "INVALID_CREDENTIAL")
    }
    credential = saved
  }

  public func clearCredential() {
    credential = nil
    generation &+= 1
  }

  private static func isValidCredential(_ credential: SessionCredential, now: Date) -> Bool {
    guard credential.name == cookieName, credential.expires > now,
      credential.expires.timeIntervalSince(now) <= sessionLifetime + 60,
      credential.value.utf8.count <= 4096
    else { return false }
    let parts = credential.value.split(separator: ".", omittingEmptySubsequences: false)
    return parts.count == 3
      && parts.allSatisfy { part in
        !part.isEmpty
          && part.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45
              || $0 == 95
          }
      }
  }

  public func session() async throws -> Session {
    _ = sessionCredential()
    let operationGeneration = generation
    let result: Session = try await request(path: ["session"])
    guard generation == operationGeneration else { throw CancellationError() }
    if !result.authenticated { clearCredential() }
    return result
  }

  @discardableResult
  public func login(login: String, password: String) async throws -> Session {
    clearCredential()
    let operationGeneration = generation
    let result: Session = try await request(
      path: ["login"], method: "POST",
      body: encoded(LoginInput(login: login, password: password)))
    guard generation == operationGeneration else { throw CancellationError() }
    guard result.authenticated, !result.requiresLogin || sessionCredential() != nil else {
      clearCredential()
      throw APIError(
        message: "Не удалось сохранить защищённую сессию. Войдите снова.",
        code: "INVALID_SESSION")
    }
    return result
  }

  public func logout() async throws {
    let operationGeneration = generation
    // A slow logout must not delete a newer login/Keychain restore while this actor is suspended.
    defer { if generation == operationGeneration { clearCredential() } }
    let _: Session = try await request(path: ["logout"], method: "POST", body: Data("{}".utf8))
  }

  public func bootstrap() async throws -> Bootstrap { try await request(path: ["bootstrap"]) }

  public func habits() async throws -> [Habit] {
    let result: HabitsEnvelope = try await request(path: ["habits"])
    return result.habits
  }

  public func createTask(_ input: TaskInput) async throws -> RitmTask {
    try await request(path: ["tasks"], method: "POST", body: encoded(input))
  }

  /// The existing task API has no expected-version contract. Send only the changed fields;
  /// do not present this endpoint as conflict-protected or replay writes automatically.
  public func setTaskCompleted(id: String, completed: Bool, occurrenceDate: String? = nil)
    async throws -> RitmTask
  {
    try await request(
      path: ["tasks", try validatedID(id)], method: "PATCH",
      body: encoded(TaskCompletionInput(completed: completed, occurrenceDate: occurrenceDate)))
  }

  public func createHabit(_ input: HabitInput) async throws -> Habit {
    let result: HabitEnvelope = try await request(
      path: ["habits"], method: "POST", body: encoded(input))
    return result.habit
  }

  public func setHabitDay(id: String, date: String, completed: Bool, expectedUpdatedAt: String)
    async throws -> Habit
  {
    guard HabitSchedule.isValidDate(date), !expectedUpdatedAt.isEmpty else {
      throw APIError(
        message: "Обновите привычку перед изменением.", status: 400, code: "INVALID_INPUT")
    }
    let result: HabitEnvelope = try await request(
      path: ["habits", try validatedID(id), "days", date],
      method: "PATCH",
      body: encoded(
        HabitCompletionInput(completed: completed, expectedUpdatedAt: expectedUpdatedAt)))
    return result.habit
  }

  public func saveSettings(_ settings: AccountSettings) async throws -> AccountSettings {
    try await request(path: ["settings"], method: "PATCH", body: encoded(settings))
  }

  public func googleStatus() async throws -> GoogleCalendarStatus {
    try await request(path: ["integrations", "google", "status"])
  }

  /// The server enforces that timeZone is the account's configured zone.
  public func googleEvents(from: String, to: String, timeZone: String) async throws
    -> GoogleCalendarResult
  {
    guard HabitSchedule.isValidDate(from), HabitSchedule.isValidDate(to), from <= to,
      TimeZone(identifier: timeZone) != nil
    else {
      throw APIError(message: "Некорректный период календаря.", status: 400, code: "INVALID_INPUT")
    }
    return try await request(
      path: ["integrations", "google", "events"],
      query: [
        URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to),
        URLQueryItem(name: "timeZone", value: timeZone),
      ])
  }

  private func validatedID(_ id: String) throws -> String {
    guard UUID(uuidString: id) != nil else {
      throw APIError(
        message: "Некорректный идентификатор записи.", status: 400, code: "INVALID_INPUT")
    }
    return id
  }

  private func encoded<T: Encodable>(_ value: T) throws -> Data {
    do { return try JSONEncoder().encode(value) } catch {
      // This failure occurs before any network I/O, so it cannot represent an uncertain write.
      throw APIError(
        message: "Проверьте данные перед сохранением.", status: 400, code: "INVALID_INPUT")
    }
  }

  private func request<T: Decodable & Sendable>(
    path: [String], method: String = "GET",
    query: [URLQueryItem] = [], body: Data? = nil,
    timeout: TimeInterval = 30
  ) async throws -> T {
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
    // Every segment originates from this client or a validated UUID/date, never a caller URL.
    components.path = "/api/" + path.joined(separator: "/")
    if !query.isEmpty { components.queryItems = query }
    guard let url = components.url else {
      throw APIError(message: "Некорректный адрес запроса.", status: 400, code: "INVALID_REQUEST")
    }
    var request = URLRequest(
      url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
    request.httpMethod = method
    request.httpShouldHandleCookies = false
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(language.rawValue, forHTTPHeaderField: "Accept-Language")
    request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    if let credential = sessionCredential() {
      request.setValue("\(credential.name)=\(credential.value)", forHTTPHeaderField: "Cookie")
    }
    if method != "GET" && method != "HEAD" {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = body ?? Data("{}".utf8)
    }
    let requestGeneration = generation
    let data: Data
    let response: HTTPURLResponse
    do {
      (data, response) = try await transport.send(request)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    } catch let error as APIError {
      throw error
    } catch {
      // Never surface raw request/cookie/provider diagnostics into the UI or logs.
      throw APIError(
        message: "Не удалось связаться с Ritm. Проверьте подключение.", code: "NETWORK")
    }
    guard generation == requestGeneration else { throw CancellationError() }
    guard let responseURL = response.url,
      responseURL.scheme == baseURL.scheme, responseURL.host == baseURL.host,
      responseURL.port == baseURL.port
    else {
      throw APIError(message: "Перенаправление заблокировано.", code: "REDIRECT_BLOCKED")
    }
    guard !(300...399).contains(response.statusCode) else {
      throw APIError(
        message: "Перенаправление заблокировано.", status: response.statusCode,
        code: "REDIRECT_BLOCKED")
    }
    guard data.count <= 8 * 1024 * 1024 else {
      throw APIError(message: "Ответ сервера слишком большой.", code: "INVALID_RESPONSE")
    }
    let decoder = JSONDecoder()
    guard (200...299).contains(response.statusCode) else {
      let error = try? decoder.decode(ErrorBody.self, from: data)
      if response.statusCode == 401 && error?.code == "AUTH_REQUIRED" { clearCredential() }
      let rawDelay =
        error?.retryAfterSeconds
        ?? response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
      let delay =
        response.statusCode == 429 ? rawDelay.flatMap { (1...3600).contains($0) ? $0 : nil } : nil
      throw APIError(
        message: error?.error ?? "Не удалось выполнить действие.", status: response.statusCode,
        code: error?.code, retryAfterSeconds: delay)
    }
    guard
      response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("application/json")
        == true
    else {
      throw APIError(
        message: "Сервер вернул некорректный ответ.", status: 502, code: "INVALID_RESPONSE")
    }
    let result: T
    do { result = try decoder.decode(T.self, from: data) } catch {
      throw APIError(
        message: "Не удалось прочитать ответ Ritm.", status: 502, code: "INVALID_RESPONSE")
    }
    // Authentication state can only be set by the direct login route, never bootstrap/content responses.
    if path == ["login"] { receiveSessionCookie(from: response) }
    return result
  }

  private func receiveSessionCookie(from response: HTTPURLResponse) {
    guard let header = response.value(forHTTPHeaderField: "Set-Cookie") else { return }
    let parts = header.split(separator: ";", omittingEmptySubsequences: false).map {
      $0.trimmingCharacters(in: .whitespaces)
    }
    guard let first = parts.first, let equals = first.firstIndex(of: "=") else { return }
    let name = String(first[..<equals])
    let value = String(first[first.index(after: equals)...])
    var attributes = [String: String]()
    for part in parts.dropFirst() {
      let attribute = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard let key = attribute.first else { return }
      let normalized = key.trimmingCharacters(in: .whitespaces).lowercased()
      guard attributes[normalized] == nil else { return }
      attributes[normalized] =
        attribute.count == 2 ? String(attribute[1]).trimmingCharacters(in: .whitespaces) : ""
    }
    guard name == Self.cookieName, attributes["secure"] != nil, attributes["httponly"] != nil,
      attributes["domain"] == nil, attributes["path"] == "/",
      attributes["samesite"]?.lowercased() == "strict",
      let maxAge = attributes["max-age"].flatMap(TimeInterval.init), maxAge.isFinite,
      maxAge > 0, maxAge <= Self.sessionLifetime
    else { return }
    let now = Date()
    let candidate = SessionCredential(
      name: name, value: value, expires: now.addingTimeInterval(maxAge))
    if Self.isValidCredential(candidate, now: now) { credential = candidate }
  }
}

extension APIClient {
  public func updateTask(id: String, task: TaskInput) async throws -> RitmTask {
    try await request(path: ["tasks", try validatedID(id)], method: "PATCH", body: encoded(task))
  }

  public func updateTask(id: String, patch: TaskPatch) async throws -> RitmTask {
    try await request(path: ["tasks", try validatedID(id)], method: "PATCH", body: encoded(patch))
  }

  public func deleteTask(id: String) async throws -> RitmTask {
    let result: DeletedTaskEnvelope = try await request(
      path: ["tasks", try validatedID(id)], method: "DELETE")
    return result.deletedTask
  }

  public func restoreTask(_ task: RitmTask) async throws -> RitmTask {
    try await request(
      path: ["tasks", "restore"], method: "POST", body: encoded(TaskRestoreInput(task: task)))
  }

  public func transferTaskToGoogle(id: String) async throws -> GoogleTransferResult {
    try await request(path: ["tasks", try validatedID(id), "google"], method: "POST")
  }

  public func updateHabit(id: String, habit: HabitInput, expectedUpdatedAt: String) async throws
    -> Habit
  {
    let result: HabitEnvelope = try await request(
      path: ["habits", try validatedID(id)], method: "PATCH",
      body: encoded(HabitUpdateInput(habit: habit, expectedUpdatedAt: expectedUpdatedAt)))
    return result.habit
  }

  public func setHabitProgress(id: String, date: String, count: Int, expectedUpdatedAt: String)
    async throws -> Habit
  {
    guard HabitSchedule.isValidDate(date), (0...10_000).contains(count) else {
      throw invalidInput()
    }
    let result: HabitEnvelope = try await request(
      path: ["habits", try validatedID(id), "days", date, "progress"], method: "PATCH",
      body: encoded(HabitProgressInput(count: count, expectedUpdatedAt: expectedUpdatedAt)))
    return result.habit
  }

  public func deleteHabit(id: String, expectedUpdatedAt: String) async throws {
    let result: DeletedEnvelope = try await request(
      path: ["habits", try validatedID(id)], method: "DELETE",
      body: encoded(VersionInput(expectedUpdatedAt: expectedUpdatedAt)))
    try requireDeleted(result)
  }

  public func finance() async throws -> [FinanceEntry] {
    let result: FinanceEnvelope = try await request(path: ["finance"])
    return result.entries
  }

  public func createFinanceEntry(_ entry: FinanceEntryInput) async throws -> FinanceEntry {
    let result: FinanceEntryEnvelope = try await request(
      path: ["finance"], method: "POST", body: encoded(entry))
    return result.entry
  }

  public func updateFinanceEntry(id: String, entry: FinanceEntryInput, expectedUpdatedAt: String)
    async throws -> FinanceEntry
  {
    let result: FinanceEntryEnvelope = try await request(
      path: ["finance", try validatedID(id)], method: "PATCH",
      body: encoded(FinanceUpdateInput(entry: entry, expectedUpdatedAt: expectedUpdatedAt)))
    return result.entry
  }

  public func deleteFinanceEntry(id: String, expectedUpdatedAt: String) async throws {
    let result: DeletedEnvelope = try await request(
      path: ["finance", try validatedID(id)], method: "DELETE",
      body: encoded(VersionInput(expectedUpdatedAt: expectedUpdatedAt)))
    try requireDeleted(result)
  }

  public func createGoogleEvent(event: GoogleEventInput, requestId: String) async throws
    -> GoogleCalendarEvent
  {
    try await request(
      path: ["integrations", "google", "events"], method: "POST",
      body: encoded(GoogleEventCreateInput(event: event, requestId: try validatedID(requestId))))
  }

  public func updateGoogleEvent(id: String, event: GoogleEventInput, etag: String) async throws
    -> GoogleCalendarEvent
  {
    try await request(
      path: ["integrations", "google", "events", try validatedGoogleID(id)], method: "PATCH",
      body: encoded(GoogleEventUpdateInput(event: event, etag: etag)))
  }

  public func deleteGoogleEvent(id: String, etag: String) async throws {
    let result: DeletedEnvelope = try await request(
      path: ["integrations", "google", "events", try validatedGoogleID(id)],
      method: "DELETE", body: encoded(GoogleVersionInput(etag: etag)))
    try requireDeleted(result)
  }

  public func completeGoogleTask(event: GoogleCalendarEvent, completed: Bool) async throws
    -> GoogleCalendarEvent
  {
    guard let task = event.googleTask else {
      throw APIError(
        message: "Подключите Google Tasks, чтобы отмечать выполнение.", status: 400,
        code: "GOOGLE_TASKS_REQUIRED")
    }
    let result: GoogleEventEnvelope = try await request(
      path: ["integrations", "google", "events", try validatedGoogleID(event.id), "task"],
      method: "PATCH",
      body: encoded(
        GoogleTaskInput(
          etag: event.etag, taskEtag: task.etag, completed: completed,
          connectionId: task.connectionId)))
    return result.event
  }

  public func googleConfiguration() async throws -> GoogleOAuthSetup {
    try await request(path: ["integrations", "google", "configuration"])
  }
  public func configureGoogle(_ configuration: GoogleOAuthSetupInput) async throws
    -> GoogleOAuthSetup
  {
    try await request(
      path: ["integrations", "google", "configuration"], method: "POST",
      body: encoded(configuration))
  }
  public func removeGoogleConfiguration() async throws -> GoogleOAuthSetup {
    try await request(path: ["integrations", "google", "configuration"], method: "DELETE")
  }
  /// Starting OAuth alone is insufficient: its HttpOnly correlation cookie must remain in the
  /// callback's browser session. The native UI uses the fixed web settings page for that flow.
  public func connectGoogle(extendedColors: Bool? = nil, tasks: Bool? = nil) async throws
    -> GoogleAuthorization
  {
    try await request(
      path: ["integrations", "google", "connect"], method: "POST",
      body: encoded(GoogleConnectInput(extendedColors: extendedColors, tasks: tasks)))
  }
  public func disconnectGoogle() async throws -> GoogleCalendarStatus {
    try await request(path: ["integrations", "google", "connection"], method: "DELETE")
  }

  public func configureAI(apiKey: String, model: String) async throws -> AIStatus {
    try await request(
      path: ["settings", "openai"], method: "POST",
      body: encoded(AIConfigurationInput(apiKey: apiKey, model: model)))
  }
  public func disconnectAI() async throws -> AIStatus {
    try await request(path: ["settings", "openai"], method: "DELETE")
  }
  public func telegramStatus() async throws -> TelegramStatus {
    try await request(path: ["integrations", "telegram", "status"])
  }
  public func configureTelegram(botToken: String) async throws -> TelegramStatus {
    try await request(
      path: ["integrations", "telegram", "configuration"], method: "POST",
      body: encoded(TelegramConfigurationInput(botToken: botToken)))
  }
  public func pairTelegram() async throws -> TelegramStatus {
    try await request(path: ["integrations", "telegram", "pairing"], method: "POST")
  }
  public func disconnectTelegram() async throws -> TelegramStatus {
    try await request(path: ["integrations", "telegram", "connection"], method: "DELETE")
  }
  public func saveTelegramReminders(enabled: Bool, leadMinutes: Int) async throws -> TelegramStatus
  {
    guard [0, 5, 10, 15, 30, 60].contains(leadMinutes) else { throw invalidInput() }
    return try await request(
      path: ["integrations", "telegram", "reminders"], method: "PATCH",
      body: encoded(TelegramRemindersInput(enabled: enabled, leadMinutes: leadMinutes)))
  }
  public func testTelegramReminder() async throws {
    let result: OKEnvelope = try await request(
      path: ["integrations", "telegram", "reminders", "test"], method: "POST")
    guard result.ok else { throw invalidResponse() }
  }

  public func createConversation() async throws -> Conversation {
    try await request(path: ["conversations"], method: "POST")
  }
  public func deleteConversation(id: String) async throws {
    let result: DeletedEnvelope = try await request(
      path: ["conversations", try validatedID(id)], method: "DELETE")
    try requireDeleted(result)
  }
  public func chat(
    conversationId: String? = nil, message: String, requestId: String,
    mode: ChatMode? = nil, reviewMessageId: String? = nil
  ) async throws -> Conversation {
    if let conversationId { _ = try validatedID(conversationId) }
    if let reviewMessageId {
      _ = try validatedID(reviewMessageId)
      guard mode == .ideaReview, conversationId != nil else { throw invalidInput() }
    }
    // Server assistant/review timeouts are 90/100 seconds; ordinary reads retain 30 seconds.
    // The caller preserves requestId for an intentional retry. This client never retries writes.
    return try await request(
      path: ["chat"], method: "POST",
      body: encoded(
        ChatInput(
          conversationId: conversationId, message: message,
          requestId: try validatedID(requestId), mode: mode, reviewMessageId: reviewMessageId)),
      timeout: 120)
  }
  public func proposals(
    action: ProposalAction, conversationId: String, messageId: String, proposalIds: [String]
  ) async throws -> ProposalResult {
    let body = try proposalInput(
      conversationId: conversationId, messageId: messageId, proposalIds: proposalIds)
    return try await request(
      path: ["proposals", action.rawValue], method: "POST", body: encoded(body))
  }
  public func reject(conversationId: String, messageId: String, proposalIds: [String]) async throws
    -> Conversation
  {
    let body = try proposalInput(
      conversationId: conversationId, messageId: messageId, proposalIds: proposalIds)
    return try await request(path: ["proposals", "reject"], method: "POST", body: encoded(body))
  }

  private func proposalInput(conversationId: String, messageId: String, proposalIds: [String])
    throws -> ProposalInput
  {
    guard (1...20).contains(proposalIds.count), Set(proposalIds).count == proposalIds.count else {
      throw invalidInput()
    }
    return ProposalInput(
      conversationId: try validatedID(conversationId), messageId: try validatedID(messageId),
      proposalIds: try proposalIds.map { try validatedID($0) })
  }
  private func validatedGoogleID(_ id: String) throws -> String {
    guard (5...1024).contains(id.utf8.count),
      id.utf8.allSatisfy({
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45
          || $0 == 95
      })
    else { throw invalidInput() }
    return id
  }
  private func invalidInput() -> APIError {
    APIError(message: "Проверьте данные перед сохранением.", status: 400, code: "INVALID_INPUT")
  }
  private func invalidResponse() -> APIError {
    APIError(message: "Сервер не подтвердил действие.", status: 502, code: "INVALID_RESPONSE")
  }
  private func requireDeleted(_ result: DeletedEnvelope) throws {
    if !result.deleted { throw invalidResponse() }
  }
}

private struct LoginInput: Encodable {
  let login: String
  let password: String
}
private struct TaskCompletionInput: Encodable {
  let completed: Bool
  let occurrenceDate: String?
}
private struct HabitCompletionInput: Encodable {
  let completed: Bool
  let expectedUpdatedAt: String
}
private struct HabitEnvelope: Decodable, Sendable { let habit: Habit }
private struct HabitsEnvelope: Decodable, Sendable { let habits: [Habit] }
private struct ErrorBody: Decodable {
  let error: String
  let code: String?
  let retryAfterSeconds: Int?
}
private struct DeletedTaskEnvelope: Decodable, Sendable { let deletedTask: RitmTask }
private struct TaskRestoreInput: Encodable { let task: RitmTask }
private struct HabitUpdateInput: Encodable {
  let habit: HabitInput
  let expectedUpdatedAt: String
}
private struct HabitProgressInput: Encodable {
  let count: Int
  let expectedUpdatedAt: String
}
private struct VersionInput: Encodable { let expectedUpdatedAt: String }
private struct DeletedEnvelope: Decodable, Sendable { let deleted: Bool }
private struct OKEnvelope: Decodable, Sendable { let ok: Bool }
private struct FinanceEnvelope: Decodable, Sendable { let entries: [FinanceEntry] }
private struct FinanceEntryEnvelope: Decodable, Sendable { let entry: FinanceEntry }
private struct FinanceUpdateInput: Encodable {
  let entry: FinanceEntryInput
  let expectedUpdatedAt: String
}
private struct GoogleEventCreateInput: Encodable {
  let event: GoogleEventInput
  let requestId: String
}
private struct GoogleEventUpdateInput: Encodable {
  let event: GoogleEventInput
  let etag: String
}
private struct GoogleVersionInput: Encodable { let etag: String }
private struct GoogleEventEnvelope: Decodable, Sendable { let event: GoogleCalendarEvent }
private struct GoogleTaskInput: Encodable {
  let etag: String
  let taskEtag: String
  let completed: Bool
  let connectionId: String
}
private struct GoogleConnectInput: Encodable {
  let extendedColors: Bool?
  let tasks: Bool?
}
private struct AIConfigurationInput: Encodable {
  let apiKey: String
  let model: String
}
private struct TelegramConfigurationInput: Encodable { let botToken: String }
private struct TelegramRemindersInput: Encodable {
  let enabled: Bool
  let leadMinutes: Int
}
private struct ChatInput: Encodable {
  let conversationId: String?
  let message: String
  let requestId: String
  let mode: ChatMode?
  let reviewMessageId: String?
}
private struct ProposalInput: Encodable {
  let conversationId: String
  let messageId: String
  let proposalIds: [String]
}
