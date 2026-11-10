import RitmCore
import SwiftUI

/// Google, Telegram and OpenAI: what the server says about them and the actions on them. Every
/// write goes through `RitmStore.write`, so it is serialized and confirmed by the API.
extension SettingsModel {
  func loadIntegrations() async {
    guard !loadingIntegrations, let store, store.isSignedIn else { return }
    loadingIntegrations = true
    defer { loadingIntegrations = false }
    if let result = await store.read({ try await $0.googleStatus() }) { google = result }
    if let result = await store.read({ try await $0.googleConfiguration() }) { googleSetup = result }
    if let result = await store.read({ try await $0.telegramStatus() }) { telegram = result }
  }

  func disconnect(_ kind: IntegrationKind) async {
    guard let store else { return }
    switch kind {
    case .google:
      if let result = await store.write({ try await $0.disconnectGoogle() }) {
        google = result
        notice = text("Google Calendar отключён от Ritm.", "Google Calendar is disconnected from Ritm.")
      }
    case .ai:
      if await store.write({ try await $0.disconnectAI() }) != nil {
        notice = text("Сохранённый ключ удалён.", "The saved key was removed.")
      }
    case .telegram:
      if let result = await store.write({ try await $0.disconnectTelegram() }) { telegram = result }
    }
    await loadIntegrations()
  }

  func saveReminders(enabled: Bool, lead: Int) async {
    guard let store else { return }
    reminderDraft = ReminderDraft(enabled: enabled, lead: lead)
    defer { reminderDraft = nil }
    if let result = await store.write({
      try await $0.saveTelegramReminders(enabled: enabled, leadMinutes: lead)
    }) {
      telegram = result
      showToast(text("Сохранено", "Saved"), failed: false)
    }
  }

  func pairTelegram() async {
    guard let store else { return }
    if let result = await store.write({ try await $0.pairTelegram() }) { telegram = result }
  }

  func testTelegram() async {
    guard let store else { return }
    if await store.performMutation({ try await $0.testTelegramReminder() }) {
      showToast(
        text("Тестовое уведомление отправлено", "Test notification sent"), failed: false)
    }
  }

  /// The pairing link, only when it is Telegram's own, still valid and carries no credentials.
  var safePairingURL: URL? {
    guard let raw = telegram?.pairingUrl, let url = URL(string: raw), url.scheme == "https",
      url.host == "t.me", url.user == nil, url.password == nil,
      let expires = telegram?.pairingExpiresAt, expires > Date().timeIntervalSince1970 * 1000
    else { return nil }
    return url
  }
}
