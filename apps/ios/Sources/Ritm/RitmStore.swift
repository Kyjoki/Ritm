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
  /// True once the stored device session has been checked, so the app does not ask for a login
  /// while it is still being restored.
  private(set) var startupFinished = false
  /// The server accepted the password and wants a one-time or recovery code (LoginCard).
  private(set) var secondFactorRequired = false
  /// A sign-in problem that must stay visible next to the form (the banner clears itself).
  private(set) var loginFailure: String?
  /// Two-factor status and the signed-in devices (Settings → «Безопасность»).
  let security = SecurityStore()
  private(set) var isLoading = false
  private(set) var isMutating = false
  /// The latest error for the banners. Transient: it clears itself after `errorLifetime`, but only
  /// while it still holds the same text, so a newer message is never wiped by an older timer.
  var errorMessage: String? {
    didSet { armErrorTimer() }
  }
  @ObservationIgnored private var errorTimer: Task<Void, Never>?

  /// Seconds an error stays on screen: about 4, 6 for a long text.
  static func errorLifetime(for message: String) -> Double { message.count > 90 ? 6 : 4 }

  private func armErrorTimer() {
    errorTimer?.cancel()
    errorTimer = nil
    guard let message = errorMessage, !message.isEmpty else { return }
    let lifetime = Self.errorLifetime(for: message)
    errorTimer = Task { @MainActor [weak self] in
      // A little longer than the banner's own fade-out, which clears it first when it is on screen.
      try? await Task.sleep(for: .seconds(lifetime + 0.5))
      guard !Task.isCancelled, let self, self.errorMessage == message else { return }
      self.errorMessage = nil
    }
  }

  /// Dismisses an error the owner has seen; a newer message stays.
  func dismissError(ifMatching message: String) {
    if errorMessage == message { errorMessage = nil }
  }
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
  /// Recurring payments («Обязательные платежи»); local to this iPhone, cleared with the account.
  let payments = PaymentScheduleStore()
  /// The training log («Тренировки»); local to this iPhone and NOT cleared by sign-out or a
  /// server switch: it is the owner's own log, not account data held by the server.
  let workouts = WorkoutStore()
  /// Mirrors the training log with the server in the background; the local files stay the truth.
  let workoutSync = WorkoutSyncCoordinator()
  /// Saving finished workouts to Apple Health; local to this iPhone, not cleared by sign-out.
  let health = HealthExportStore()

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
  /// Habit ticks in flight: unsent taps per habit and day, the last server-confirmed copy, and the
  /// habits whose queue is being sent (see `tickHabit`).
  @ObservationIgnored private var habitQueue: [String: [String: Int]] = [:]
  @ObservationIgnored private var habitConfirmed: [String: Habit] = [:]
  @ObservationIgnored private var habitSending: Set<String> = []

  init() {
    let address = ServerAddressStore.load()
    serverAddress = address
    client = try? APIClient(baseURL: address.url)
    vault = SessionVault(server: address)
    // Earlier builds saved the password for silent re-sign-in; it is never kept any more.
    SessionVault.purgeLegacySavedLogin()
    workouts.alerts.language = { [weak self] in self?.language ?? .ru }
    // A workout resumed after a relaunch: reuse its lock-screen card and pending notification.
    workouts.syncAlerts()
    workouts.onWorkoutFinished = { [health] in health.exportIfEnabled($0) }
    workoutSync.configure(workouts: workouts) { [weak self] in
      guard let self, isSignedIn, let client else { return nil }
      return .init(remote: client, serverKey: serverAddress.description)
    }
    health.reconcileOnLaunch()
  }

  /// Switches this device to another server and signs it out first. The session belongs to one
  /// server (the Keychain account is the host), so the old one is erased and nothing from the
  /// previous server can reach the new one. The app never signs in to the new server by itself. The old session is not revoked over
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
    payments.reset()
    cancelSecondFactor()
    await clearAccount()
    let newVault = SessionVault(server: address)
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
    guard !started else { return }
    guard let client else {
      startupFinished = true
      return
    }
    started = true
    isLoading = true
    defer {
      isLoading = false
      startupFinished = true
      schedulePolling()
    }
    do {
      if let credential = try vault.load() { try await client.restoreCredential(credential) }
      let session = try await client.session()
      guard session.authenticated else {
        await clearAccount()
        return
      }
      isSignedIn = true
      workoutSync.request()
      await refresh()
    } catch {
      await present(error)
    }
  }

  func signIn(
    login: String, password: String, totp: String? = nil, recoveryCode: String? = nil
  ) async {
    guard !isMutating, !isLoading, let client else { return }
    let login = login.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !login.isEmpty, !password.isEmpty else {
      errorMessage = text("Введите логин и пароль.", "Enter your login and password.")
      return
    }
    isMutating = true
    errorMessage = nil
    loginFailure = nil
    generation += 1
    do {
      await client.setLanguage(language)
      let session = try await client.login(
        login: login, password: password, totp: totp, recoveryCode: recoveryCode,
        deviceName: Self.deviceName)
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
      secondFactorRequired = false
      isSignedIn = true
      isOffline = false
      nextAllowedRead = .distantPast
      featureRetryAt = nil
    } catch {
      await client.clearCredential()
      try? vault.delete()
      await presentSignInFailure(error)
    }
    isMutating = false
    if isSignedIn {
      workoutSync.request()
      await refresh()
      schedulePolling()
    }
  }

  /// Back to the login and password step.
  func cancelSecondFactor() {
    secondFactorRequired = false
    loginFailure = nil
  }

  private func presentSignInFailure(_ error: Error) async {
    guard let failure = error as? APIError else { return await present(error) }
    if failure.requiresSecondFactor {
      secondFactorRequired = true
    } else if failure.isSecondFactorInvalid {
      secondFactorRequired = true
      loginFailure = text(
        "Неверный код. Проверьте код и попробуйте ещё раз.",
        "Wrong code. Check it and try again.")
    } else if failure.status == 429 {
      loginFailure = failure.retryAfterSeconds.map {
        text(
          "Слишком много попыток. Повторите через \(Self.waitText($0, ru: true)).",
          "Too many attempts. Try again in \(Self.waitText($0, ru: false)).")
      } ?? text("Слишком много попыток. Повторите позже.", "Too many attempts. Try again later.")
    } else {
      // Wrong password or login: start again from the first step.
      if failure.status == 401 { secondFactorRequired = false }
      await present(error)
    }
  }

  private static func waitText(_ seconds: Int, ru: Bool) -> String {
    if seconds < 60 { return ru ? "\(seconds) с" : "\(seconds) s" }
    let minutes = (seconds + 59) / 60
    return ru ? "\(minutes) мин" : "\(minutes) min"
  }

  /// «iPhone (iPhone14,5)»: the model only, no personal name.
  private static var deviceName: String {
    var info = utsname()
    uname(&info)
    let model = Mirror(reflecting: info.machine).children.reduce(into: "") { text, child in
      if let byte = child.value as? Int8, byte > 0 { text.append(Character(UnicodeScalar(UInt8(byte)))) }
    }
    return DeviceLabel.make(model: model)
  }

  /// Security card actions go through the same client; a revoked session ends here like anywhere.
  func securityClient() -> APIClient? { isSignedIn ? client : nil }
  func reportSecurityFailure(_ error: Error) async { await present(error) }

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
      // A habit tick in flight shows its own, newer state; the next snapshot brings the server's.
      if habitSending.isEmpty { habits = freshHabits }
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
    let count = isCompletedToday(current) ? 0 : HabitSchedule.target(current)
    _ = await tickHabit(id: current.id, date: today, count: count)
  }

  // MARK: Habit ticks

  /// What one finished tick changed: the habit before the first unsent tap and the server's copy.
  struct HabitTick: Sendable {
    let before: Habit
    let after: Habit
  }

  /// Records a habit's progress for a day. The change shows in `habits` at once; the request goes
  /// out in the background and only this habit takes the server's answer (no snapshot reload, no
  /// global `isMutating`). Taps while a request is in flight are queued per habit and sent in
  /// order with the fresh `updatedAt`. A failed request puts the habit back, shows a toast and
  /// re-reads that habit. Returns the result only from the call that drained the queue.
  func tickHabit(id: String, date: String, count: Int) async -> HabitTick? {
    guard isSignedIn, !isOffline, !uncertainWrite, !isMutating, Date() >= nextAllowedRead,
      let index = habits.firstIndex(where: { $0.id == id })
    else { return nil }
    let current = habits[index]
    guard HabitSchedule.canMark(current, on: date, today: today) else { return nil }
    let next = max(0, min(HabitSchedule.target(current), count))
    if habitConfirmed[id] == nil { habitConfirmed[id] = current }
    habits[index] = Self.habit(current, setting: next, on: date)
    habitQueue[id, default: [:]][date] = next
    // A snapshot read started before this tap must not overwrite it.
    generation += 1
    guard !habitSending.contains(id) else { return nil }
    habitSending.insert(id)
    var result = await sendHabitQueue(id: id)
    // A tap that arrived while the failure was being reported is still queued: send it too.
    while !(habitQueue[id]?.isEmpty ?? true), isSignedIn {
      result = await sendHabitQueue(id: id) ?? result
    }
    habitSending.remove(id)
    return result
  }

  private func sendHabitQueue(id: String) async -> HabitTick? {
    guard let client, let first = habitConfirmed[id] else { return nil }
    var latest: Habit?
    while let (date, count) = habitQueue[id]?.first {
      habitQueue[id]?.removeValue(forKey: date)
      guard let base = habitConfirmed[id] else { break }
      do {
        let saved: Habit
        if base.target == nil {
          saved = try await client.setHabitDay(
            id: id, date: date, completed: count > 0, expectedUpdatedAt: base.updatedAt)
        } else {
          saved = try await client.setHabitProgress(
            id: id, date: date, count: count, expectedUpdatedAt: base.updatedAt)
        }
        guard isSignedIn else {
          habitQueue[id] = nil
          habitConfirmed[id] = nil
          return nil
        }
        habitConfirmed[id] = saved
        latest = saved
        // Newer taps are still queued: keep showing them, the last answer replaces the habit.
        if habitQueue[id]?.isEmpty ?? true, let i = habits.firstIndex(where: { $0.id == id }) {
          habits[i] = saved
        }
      } catch {
        await failHabitTick(id: id, error: error)
        return nil
      }
    }
    habitQueue[id] = nil
    habitConfirmed[id] = nil
    return latest.map { HabitTick(before: first, after: $0) }
  }

  /// Rolls the habit back to the last copy the server confirmed, tells the owner, and re-reads it.
  private func failHabitTick(id: String, error: Error) async {
    let restore = habitConfirmed[id]
    habitQueue[id] = nil
    habitConfirmed[id] = nil
    if let restore, let i = habits.firstIndex(where: { $0.id == id }) { habits[i] = restore }
    await present(error)
    guard isSignedIn else { return }
    let detail = errorMessage
    errorMessage = nil
    toasts.show(
      detail
        ?? text(
          "Не удалось сохранить отметку. Изменение отменено.",
          "Could not save the mark. The change was undone."))
    // Only this habit takes the server's copy; the others are left as they are.
    guard let client, let fresh = try? await client.habits().first(where: { $0.id == id }),
      habitConfirmed[id] == nil, let i = habits.firstIndex(where: { $0.id == id })
    else { return }
    habits[i] = fresh
  }

  /// The habit with `count` recorded on `date`, as the server will store it.
  private static func habit(_ habit: Habit, setting count: Int, on date: String) -> Habit {
    var next = habit
    let complete = count >= HabitSchedule.target(habit)
    if habit.target != nil || habit.progressByDate?[date] != nil {
      var progress = next.progressByDate ?? [:]
      progress[date] = habit.target != nil ? count : (complete ? 1 : 0)
      next.progressByDate = progress
    }
    var dates = next.completedDates.filter { $0 != date }
    if complete { dates.append(date) }
    next.completedDates = dates.sorted()
    return next
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
    wallet.reset()
    walletFolder.disconnect()
    payments.reset()
    workoutSync.reset()
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
      workouts.syncAlerts()
      schedulePolling()
      workoutSync.request()
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

  private func present(_ error: Error) async {
    if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
    lastFailure = error as? APIError
    if let failure = error as? APIError {
      if failure.requiresAuthentication {
        // The device session expired or was revoked. The action that hit it is not retried;
        // Settings shows the sign-in form again.
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
    security.reset()
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
