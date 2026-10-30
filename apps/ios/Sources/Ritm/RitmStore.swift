import Foundation
import Observation
import RitmCore

/// Where a tapped finance notice should land; FinanceView consumes it and sets it back to nil.
struct FinanceFocus: Equatable {
  let cardID: String
  let entryID: String?
}

/// UI state only. The existing Ritm server remains authoritative.
@MainActor @Observable
final class RitmStore {
  private(set) var isSignedIn = false
  private(set) var isLoading = false
  private(set) var isMutating = false
  var errorMessage: String?
  private(set) var bootstrap: Bootstrap?
  private(set) var habits: [Habit] = []
  private(set) var todayEvents: [GoogleCalendarEvent] = []
  private(set) var calendarStatusText = ""
  private(set) var calendarReady = false
  private(set) var calendarPartial = false
  private(set) var calendarFailed = false
  private(set) var googleStatus: GoogleCalendarStatus?
  private(set) var googleTasks: GoogleTasksStatus?
  private(set) var lastSyncedAt: Date?
  private(set) var isOffline = false
  private(set) var uncertainWrite = false
  private(set) var now = Date()
  private(set) var pendingTheme: Theme?
  /// When a feature-specific limit (for example the idea review) allows the next retry.
  private(set) var featureRetryAt: Date?
  /// The API failure behind errorMessage, for screens that explain it in place (the assistant).
  private(set) var lastFailure: APIError?
  /// Finance rows live here only for the Finance page and the notice centre. They are never
  /// passed to the assistant or to any AI request.
  private(set) var financeEntries: [FinanceEntry] = []
  private(set) var financeLoaded = false
  private(set) var financeFailed = false
  var financeFocus: FinanceFocus?
  let notices = FinanceNoticeCenter()
  let toasts = RitmToastCenter()
  /// Apple Wallet purchases waiting for confirmation; local to this iPhone.
  let wallet = WalletInboxStore()
  /// The Files folder whose `purchases.txt` the Shortcuts automation appends to; local only.
  let walletFolder = WalletFolderSource()

  /// The Ritm server this device talks to. Changed only through `changeServer(to:)`.
  private(set) var serverAddress: ServerAddress
  @ObservationIgnored private var client: APIClient?
  @ObservationIgnored private var vault: SessionVault
  @ObservationIgnored private let notifications = LocalNotifications()
  @ObservationIgnored private var started = false
  @ObservationIgnored private var active = true
  @ObservationIgnored private var refreshing = false
  @ObservationIgnored private var refreshRequested = false
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var pollTask: Task<Void, Never>?
  @ObservationIgnored private var nextAllowedRead = Date.distantPast
  @ObservationIgnored private var connectionErrorShown = false

  init() {
    let address = ServerAddressStore.load()
    serverAddress = address
    client = try? APIClient(baseURL: address.url)
    vault = SessionVault(server: address)
  }

  /// Switches this device to another server and signs it out first. The session and the saved
  /// login belong to one server (the Keychain account is the host), so the old ones are erased and
  /// nothing from the previous server can reach the new one. The old session is not revoked over
  /// the network, so an unreachable old server cannot block the switch; it expires on its own.
  @discardableResult
  func changeServer(to address: ServerAddress) async -> Bool {
    guard !isMutating, !isLoading, address != serverAddress,
      let newClient = try? APIClient(baseURL: address.url)
    else { return false }
    isMutating = true
    generation += 1
    pollTask?.cancel()
    wallet.reset()
    walletFolder.disconnect()
    vault.forgetLogin()
    await clearAccount()
    let newVault = SessionVault(server: address)
    newVault.forgetLogin()
    try? newVault.delete()
    client = newClient
    vault = newVault
    serverAddress = address
    ServerAddressStore.save(address)
    errorMessage = nil
    isMutating = false
    return true
  }

  var language: Language {
    bootstrap?.settings.language
      ?? (Locale.preferredLanguages.first?.hasPrefix("ru") == true ? .ru : .en)
  }
  var timeZone: String { bootstrap?.settings.timeZone ?? "Asia/Qyzylorda" }
  var today: String { HabitSchedule.dateKey(now, timeZone: timeZone) }
  var todayLabel: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language == .ru ? "ru_RU" : "en_US")
    formatter.timeZone = TimeZone(identifier: timeZone)
    formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
    return formatter.string(from: now)
  }
  func text(_ ru: String, _ en: String) -> String { language == .ru ? ru : en }

  var googleConnected: Bool { googleStatus?.status == .connected }
  /// App.tsx `googlePending`: the status or the first schedule is still on its way.
  var googlePending: Bool {
    !calendarFailed && (googleStatus == nil || (googleConnected && !calendarReady))
  }
  /// App.tsx `googleUncertain`: connected, but the schedule is missing, failed or partial.
  var googleUncertain: Bool {
    googleConnected && (!calendarReady || calendarPartial || calendarFailed)
  }
  /// The current wall-clock minute in the account zone.
  var minuteOfDay: Int {
    let calendar = FeatureDate.calendar(timeZone)
    return calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
  }

  func requestNotificationPermission() async -> Bool {
    let allowed = await notifications.requestPermission()
    if !allowed {
      errorMessage = text(
        "Разрешите уведомления Ritm в настройках iPhone.",
        "Allow Ritm notifications in iPhone Settings.")
    }
    return allowed
  }

  func updateLocalNotifications() async {
    let ticket = generation
    guard isSignedIn, let snapshot = bootstrap,
      let credential = await client?.sessionCredential(), ticket == generation
    else {
      if !isSignedIn { notifications.clear() }
      return
    }
    await notifications.update(snapshot: snapshot, until: credential.expires, now: Date())
  }

  /// Apply the acknowledged preferences before reconciliation. In particular,
  /// a failed follow-up read must not reschedule reminders just switched off.
  func saveSettings(_ value: AccountSettings) async -> AccountSettings? {
    await write { client in
      let saved = try await client.saveSettings(value)
      self.bootstrap?.settings = saved
      if !saved.notifications { self.notifications.clear() }
      await client.setLanguage(saved.language)
      return saved
    }
  }

  /// The account theme drives the whole app, as on the web (App.tsx). Before sign-in the web
  /// starts light (public/theme-init.js).
  var theme: Theme { pendingTheme ?? bootstrap?.settings.theme ?? .light }

  /// The header toggle switches at once and saves the opposite of what is shown to the account.
  /// A failed save falls back to the server value.
  func toggleTheme(showingDark: Bool) async {
    guard var settings = bootstrap?.settings, pendingTheme == nil else { return }
    settings.theme = showingDark ? .light : .dark
    pendingTheme = settings.theme
    _ = await saveSettings(settings)
    pendingTheme = nil
  }

  var canWrite: Bool {
    isSignedIn && !isLoading && !isMutating && !isOffline && !uncertainWrite
      && Date() >= nextAllowedRead
  }

  /// Every feature shares the same session and invalidation boundary. A response
  /// from before logout or a mutation must never repopulate a feature's state.
  func read<Value: Sendable>(_ operation: @MainActor (APIClient) async throws -> Value) async
    -> Value?
  {
    guard isSignedIn, active, !isMutating, Date() >= nextAllowedRead, let client else { return nil }
    let ticket = generation
    do {
      let value = try await operation(client)
      guard ticket == generation, isSignedIn, !Task.isCancelled else { return nil }
      return value
    } catch {
      guard ticket == generation, !Task.isCancelled else { return nil }
      await present(error)
      return nil
    }
  }

  @discardableResult
  func performMutation(_ operation: @MainActor (APIClient) async throws -> Void) async -> Bool {
    await write { client in
      try await operation(client)
      return true
    } == true
  }

  func isScheduledToday(_ habit: Habit) -> Bool { HabitSchedule.isScheduled(habit, on: today) }
  func isCompletedToday(_ habit: Habit) -> Bool { HabitSchedule.isComplete(habit, on: today) }
  func habitProgressText(_ habit: Habit) -> String {
    if let target = habit.target, target > 1 {
      return "\(HabitSchedule.progress(habit, on: today))/\(target) \(habit.unit ?? "")"
    }
    return isCompletedToday(habit)
      ? text("Выполнено", "Completed") : text("На сегодня", "For today")
  }
  func eventTimeText(_ event: GoogleCalendarEvent) -> String {
    if event.allDay { return text("Весь день", "All day") }
    guard let start = parseISO(event.start.dateTime), let end = parseISO(event.end.dateTime) else {
      return text("Смотрите время в календаре", "See time in Calendar")
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: timeZone)
    formatter.dateFormat = "h:mm a"
    return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
  }

  func start() async {
    guard !started, let client else { return }
    started = true
    isLoading = true
    defer {
      isLoading = false
      schedulePolling()
    }
    do {
      if let credential = try vault.load() { try await client.restoreCredential(credential) }
      var session = try await client.session()
      if !session.authenticated, await signInAgain() { session = try await client.session() }
      guard session.authenticated else {
        await clearAccount()
        return
      }
      isSignedIn = true
      await refresh()
    } catch {
      await present(error)
    }
  }

  func signIn(login: String, password: String) async {
    guard !isMutating, !isLoading, let client else { return }
    let login = login.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !login.isEmpty, !password.isEmpty else {
      errorMessage = text("Введите логин и пароль.", "Enter your login and password.")
      return
    }
    isMutating = true
    errorMessage = nil
    generation += 1
    do {
      await client.setLanguage(language)
      let session = try await client.login(login: login, password: password)
      guard session.authenticated, session.requiresLogin,
        let credential = await client.sessionCredential()
      else {
        await clearAccount()
        errorMessage = text(
          "Сервер не подтвердил защищённую сессию.", "The server did not confirm a secure session.")
        isMutating = false
        return
      }
      try vault.save(credential)
      // Remembered on this iPhone only, so the app signs in again by itself (see SessionVault).
      try? vault.saveLogin(.init(login: login, password: password))
      isSignedIn = true
      isOffline = false
      nextAllowedRead = .distantPast
      featureRetryAt = nil
    } catch {
      await client.clearCredential()
      try? vault.delete()
      await present(error)
    }
    isMutating = false
    if isSignedIn {
      await refresh()
      schedulePolling()
    }
  }

  func refresh() async { await loadSnapshot() }

  /// GET /finance through the shared read boundary; updates entries, then the notice centre.
  func reloadFinance() async {
    // `read` also returns nil when it is paused, cancelled or signed out; only a thrown request
    // counts as a failed load.
    var requestFailed = false
    let loaded = await read { client in
      do { return try await client.finance() } catch {
        requestFailed = true
        throw error
      }
    }
    guard let fresh = loaded else {
      if requestFailed { financeFailed = true }
      return
    }
    applyFinance(fresh)
  }

  private func applyFinance(_ entries: [FinanceEntry]) {
    financeEntries = entries
    financeLoaded = true
    financeFailed = false
    notices.update(entries: entries, today: today)
  }

  /// Part of the snapshot, so it also runs after writes (when `read` is paused) and on the poll.
  private func refreshFinance(ticket: Int) async {
    guard let client else { return }
    do {
      let fresh = try await client.finance()
      guard ticket == generation, isSignedIn, !Task.isCancelled else { return }
      applyFinance(fresh)
    } catch {
      guard ticket == generation, !Task.isCancelled else { return }
      financeFailed = true
      if let failure = error as? APIError, failure.requiresAuthentication { await present(error) }
    }
  }

  private func loadSnapshot(afterWrite: Bool = false) async {
    guard isSignedIn, active, !isMutating || afterWrite,
      Date() >= nextAllowedRead, let client
    else { return }
    if refreshing {
      refreshRequested = true
      return
    }
    refreshRequested = false
    refreshing = true
    let ticket = generation
    if bootstrap == nil { isLoading = true }
    defer {
      refreshing = false
      isLoading = false
      if refreshRequested, active, isSignedIn, !isMutating {
        refreshRequested = false
        Task { await refresh() }
      }
    }
    do {
      // Keep authenticated reads ordered: a 401 must not be hidden by a sibling
      // request cancelled when APIClient clears its credential generation.
      let freshAccount = try await client.bootstrap()
      guard ticket == generation, isSignedIn, !Task.isCancelled else { return }
      let freshHabits = try await client.habits()
      guard ticket == generation, isSignedIn, !Task.isCancelled else { return }
      bootstrap = freshAccount
      habits = freshHabits
      now = Date()
      isOffline = false
      if connectionErrorShown {
        errorMessage = nil
        connectionErrorShown = false
      }
      lastSyncedAt = now
      await client.setLanguage(freshAccount.settings.language)
      await refreshCalendar(ticket: ticket)
      await refreshFinance(ticket: ticket)
      if ticket == generation, isSignedIn, let credential = await client.sessionCredential() {
        await notifications.update(snapshot: freshAccount, until: credential.expires, now: now)
      }
    } catch {
      guard ticket == generation, !Task.isCancelled else { return }
      await present(error)
    }
  }

  func toggleHabit(_ habit: Habit) async {
    now = Date()
    guard let current = habits.first(where: { $0.id == habit.id }),
      current.archived != true, isScheduledToday(current)
    else { return }
    let date = today
    let completed = !isCompletedToday(current)
    _ = await mutate { client in
      _ = try await client.setHabitDay(
        id: current.id, date: date, completed: completed, expectedUpdatedAt: current.updatedAt)
    }
  }

  private func mutate(_ operation: @MainActor (APIClient) async throws -> Void) async -> Bool {
    await performMutation(operation)
  }

  /// Mutations are serialized, confirmed by the API, and never automatically
  /// retried. Views retain their draft until this method returns a value.
  func write<Value: Sendable>(_ operation: @MainActor (APIClient) async throws -> Value) async
    -> Value?
  {
    guard isSignedIn, !isMutating, !isOffline, !uncertainWrite,
      Date() >= nextAllowedRead, let client
    else { return nil }
    now = Date()
    generation += 1  // A read started before this write cannot overwrite newer UI state.
    let ticket = generation
    isMutating = true
    notices.beginOwnWrite()
    defer { notices.endOwnWrite() }
    errorMessage = nil
    lastFailure = nil
    var result: Value?
    do { result = try await operation(client) } catch {
      guard ticket == generation else {
        isMutating = false
        return nil
      }
      await present(error)
      let failure = error as? APIError
      if isSignedIn && (failure == nil || failure?.status == 0 || (failure?.status ?? 0) >= 500) {
        uncertainWrite = true
        connectionErrorShown = false
        errorMessage = text(
          "Ответ на изменение не получен. Оно могло сохраниться. Проверьте список перед повтором.",
          "The change was not confirmed. It may have been saved. Check the list before trying again."
        )
      }
    }
    // Writes are never retried automatically: an interrupted response may have committed.
    // Reconcile before allowing the next action, without optimistic/persisted fake success.
    if isSignedIn {
      while refreshing {
        do { try await Task.sleep(for: .milliseconds(40)) } catch {
          isMutating = false
          return nil
        }
      }
      await loadSnapshot(afterWrite: true)
    }
    isMutating = false
    return ticket == generation && isSignedIn && !Task.isCancelled ? result : nil
  }

  func acknowledgeUncertainWrite() {
    uncertainWrite = false
    errorMessage = nil
  }

  func signOut() async {
    guard !isMutating, let client else { return }
    isMutating = true
    generation += 1
    pollTask?.cancel()
    var revokeFailed = false
    do { try await client.logout() } catch { revokeFailed = true }
    vault.forgetLogin()
    wallet.reset()
    walletFolder.disconnect()
    await clearAccount()
    isMutating = false
    if revokeFailed {
      errorMessage = text(
        "Вы вышли на этом iPhone. Отзыв сессии на сервере не подтверждён; она истечёт автоматически.",
        "Signed out on this iPhone. Server revocation was not confirmed; the session will expire automatically."
      )
    }
  }

  func setActive(_ value: Bool) {
    active = value
    pollTask?.cancel()
    if value {
      now = Date()
      schedulePolling()
      Task { await refresh() }
    }
  }

  private func schedulePolling() {
    pollTask?.cancel()
    guard isSignedIn, active else { return }
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(30)) } catch { return }
        guard !Task.isCancelled else { return }
        self?.now = Date()  // The greeting and «today» follow the clock even while offline.
        await self?.refresh()
      }
    }
  }

  private func refreshCalendar(ticket: Int) async {
    guard let client else { return }
    do {
      let status = try await client.googleStatus()
      guard ticket == generation, isSignedIn, !Task.isCancelled else { return }
      googleStatus = status
      guard status.status == .connected else {
        todayEvents = []
        googleTasks = nil
        calendarReady = false
        calendarPartial = false
        calendarFailed = false
        calendarStatusText = text(
          "Подключите Google Calendar в веб-версии Ritm.",
          "Connect Google Calendar in Ritm on the web.")
        return
      }
      let result = try await client.googleEvents(
        from: today, to: HabitSchedule.addDays(to: today, days: 1) ?? today, timeZone: timeZone)
      guard ticket == generation, isSignedIn, !Task.isCancelled else { return }
      todayEvents = result.events.sorted {
        ($0.start.dateTime ?? $0.start.date ?? "") < ($1.start.dateTime ?? $1.start.date ?? "")
      }
      googleTasks = result.tasks
      calendarReady = true
      calendarPartial = result.partial
      calendarFailed = false
      calendarStatusText =
        result.partial
        ? text("Google вернул часть расписания.", "Google returned a partial schedule.")
        : text("Google Calendar · синхронизировано", "Google Calendar · synced")
    } catch {
      guard ticket == generation, !Task.isCancelled else { return }
      calendarReady = false
      calendarFailed = true
      calendarStatusText = text(
        "Не удалось обновить расписание. Показаны последние полученные события.",
        "Could not refresh the schedule. Showing the last received events.")
      if let failure = error as? APIError, failure.status == 401 { await present(error) }
    }
  }

  /// Signs in with the login saved on this iPhone. A rejected login is forgotten, so the sign-in
  /// screen appears and the owner enters the new password once.
  private func signInAgain() async -> Bool {
    guard let client, let saved = vault.loadLogin() else { return false }
    do {
      let session = try await client.login(login: saved.login, password: saved.password)
      guard session.authenticated, let credential = await client.sessionCredential() else {
        return false
      }
      try vault.save(credential)
      isSignedIn = true
      isOffline = false
      return true
    } catch {
      if let failure = error as? APIError, failure.status == 401 || failure.status == 403 {
        vault.forgetLogin()
      }
      return false
    }
  }

  private func present(_ error: Error) async {
    if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
    lastFailure = error as? APIError
    if let failure = error as? APIError {
      if failure.requiresAuthentication {
        // The 8-hour session ended: sign in again with the saved login. The action that hit
        // it is not retried (writes never are); the next read or tap works.
        if await signInAgain() {
          errorMessage = nil
          Task { await refresh() }
          return
        }
        await clearAccount()
        errorMessage = text(
          "Сессия завершилась. Войдите снова.", "Your session has expired. Sign in again.")
        return
      }
      if failure.code == "NETWORK" {
        isOffline = true
        connectionErrorShown = true
      }
      if let delay = failure.retryAfterSeconds {
        let until = Date().addingTimeInterval(Double(delay))
        // Only the shared read/mutation budget (server/security.ts) pauses every request.
        // A feature's own limit (idea review, AI provider, Google) only delays that feature's
        // retry, as on the web; it must not freeze the rest of the app.
        if failure.code == "RATE_LIMIT" {
          nextAllowedRead = until
        } else {
          featureRetryAt = until
        }
      }
      errorMessage =
        failure.code == "NETWORK"
        ? text(
          "Нет связи. Проверьте данные после восстановления соединения перед повтором действия.",
          "Connection unavailable. Check your data after reconnecting before repeating an action.")
        : failure.message
    } else if error is URLError {
      isOffline = true
      connectionErrorShown = true
      errorMessage = text(
        "Нет связи. Изменения не отправлены повторно. Обновите данные перед следующим действием.",
        "Connection unavailable. Changes were not retried. Refresh before making another change.")
    } else {
      errorMessage = text(
        "Не удалось завершить действие. Попробуйте обновить данные.",
        "Could not complete the action. Try refreshing your data.")
    }
  }

  private func clearAccount() async {
    generation += 1
    pollTask?.cancel()
    isSignedIn = false
    bootstrap = nil
    habits = []
    todayEvents = []
    calendarStatusText = ""
    calendarReady = false
    calendarPartial = false
    calendarFailed = false
    googleStatus = nil
    googleTasks = nil
    financeEntries = []
    financeLoaded = false
    financeFailed = false
    financeFocus = nil
    notices.reset()
    lastSyncedAt = nil
    isOffline = false
    uncertainWrite = false
    refreshRequested = false
    connectionErrorShown = false
    try? vault.delete()
    notifications.clear()
    await client?.clearCredential()
  }

  private func parseISO(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}
