import Foundation
import Observation
import RitmCore

/// Two-factor status and the signed-in devices for Settings → «Безопасность». Servers that
/// predate the security endpoints answer 404: `unavailable` then hides the card quietly.
@MainActor @Observable
final class SecurityStore {
  private(set) var overview: SecurityOverview?
  private(set) var unavailable = false
  private(set) var busy = false
  /// A failed action, shown inside the card; the load itself never raises a banner.
  private(set) var message: String?

  func reset() {
    overview = nil
    unavailable = false
    busy = false
    message = nil
  }

  func load(using store: RitmStore) async {
    guard let client = store.securityClient() else { return }
    do {
      overview = try await client.security()
      unavailable = false
      message = nil
    } catch {
      await handle(error, store: store, hideOn404: true)
    }
  }

  func revoke(sessionID: String, using store: RitmStore) async {
    await perform(store) { try await $0.revokeSession(id: sessionID) }
  }

  func revokeOthers(using store: RitmStore) async {
    await perform(store) { try await $0.revokeOtherSessions() }
  }

  private func perform(
    _ store: RitmStore, _ action: @Sendable (APIClient) async throws -> Void
  ) async {
    guard !busy, let client = store.securityClient() else { return }
    busy = true
    message = nil
    defer { busy = false }
    do {
      try await action(client)
      overview = try await client.security()
    } catch {
      await handle(error, store: store, hideOn404: false)
    }
  }

  private func handle(_ error: Error, store: RitmStore, hideOn404: Bool) async {
    if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
    guard let failure = error as? APIError else {
      message = store.text("Не удалось выполнить действие.", "The action failed.")
      return
    }
    if failure.requiresAuthentication {
      await store.reportSecurityFailure(error)
    } else if failure.status == 404 && hideOn404 {
      unavailable = true
      overview = nil
    } else {
      message = failure.code == "NETWORK"
        ? store.text("Нет связи. Повторите позже.", "No connection. Try again later.")
        : failure.message
    }
  }
}
