import Observation
import RitmCore
import SwiftUI
import UIKit
import UserNotifications

struct ReminderDraft: Equatable {
  let enabled: Bool
  let lead: Int
}

/// The tiny confirmation under the settings pages: «Сохранено», or why a change was put back.
struct SettingsToast: Equatable, Identifiable {
  let id: Int
  let text: String
  let failed: Bool
}

/// Everything the Settings pages share: the settings draft with its autosave, and the state of
/// the integrations. A change shows on screen at once and is sent on its own a moment later, as
/// only the fields that changed (`SettingsAutosaveState` decides what goes out and when).
@MainActor @Observable
final class SettingsModel {
  /// The pause after the last edit before it is sent, so a name typed letter by letter is one
  /// request. Switches and pickers send at once (`commit`).
  static let debounce: Duration = .milliseconds(700)
  static let toastLifetime: Duration = .milliseconds(1500)
  /// How long a save waits for another request of the app to finish before it gives up.
  private static let waitSteps = 40
  private static let waitStep: Duration = .milliseconds(150)

  private(set) var state = SettingsAutosaveState(server: AccountSettings())
  private(set) var loaded = false
  private(set) var toast: SettingsToast?
  /// Why the last edit of a text field is not being saved (shown under the field).
  private(set) var heldIssue: SettingsIssue?
  var notificationError: String?
  /// iOS's answer for notifications of this app; nil until it has been asked.
  private(set) var phoneNotificationsAllowed: Bool?

  init(initial: AccountSettings? = nil) {
    guard let initial else { return }
    state = SettingsAutosaveState(server: initial)
    loaded = true
  }

  // Integrations (SettingsModel+Integrations.swift).
  var google: GoogleCalendarStatus?
  var googleSetup: GoogleOAuthSetup?
  var telegram: TelegramStatus?
  var notice: String?
  var loadingIntegrations = false
  /// The Telegram reminder choice while it is being saved, so the switch and the segment answer at once.
  var reminderDraft: ReminderDraft?

  @ObservationIgnored weak var store: RitmStore?
  @ObservationIgnored private var debounceTask: Task<Void, Never>?
  @ObservationIgnored private var toastTask: Task<Void, Never>?
  @ObservationIgnored private var toastSerial = 0
  @ObservationIgnored private var flushing = false

  var draft: AccountSettings { state.draft }
  var language: Language { store?.language ?? state.draft.language }

  func text(_ ru: String, _ en: String) -> String { language == .ru ? ru : en }

  // MARK: Draft

  /// A fresh copy of the account's settings: the first one starts the draft, later ones only
  /// move the fields that have no change of the owner waiting.
  func sync(with settings: AccountSettings?) {
    guard let settings else { return }
    if loaded {
      state.adopt(settings)
    } else {
      state = SettingsAutosaveState(server: settings)
      loaded = true
    }
  }

  /// Signing out forgets what the pages held.
  func reset() {
    debounceTask?.cancel()
    state = SettingsAutosaveState(server: AccountSettings())
    loaded = false
    google = nil
    googleSetup = nil
    telegram = nil
    notice = nil
    toast = nil
  }

  /// Shows a change now and sends it after the pause.
  func edit(_ change: AccountSettingsPatch) {
    state.edit(change)
    heldIssue = state.heldIssues.first
    debounceTask?.cancel()
    debounceTask = Task { [weak self] in
      try? await Task.sleep(for: Self.debounce)
      guard !Task.isCancelled else { return }
      await self?.flush()
    }
  }

  /// Shows a change now and sends it right away (a switch, a menu, the theme).
  func commit(_ change: AccountSettingsPatch) {
    state.edit(change)
    debounceTask?.cancel()
    Task { await flush() }
  }

  /// A text field was left or the page closed: send what is valid and put back what is not.
  func settle() async {
    debounceTask?.cancel()
    let dropped = state.revertInvalid()
    heldIssue = nil
    if let issue = dropped.first { showToast(issue.message(language), failed: true) }
    await flush()
  }

  /// The wheels move through many values; the pause sends only the one they stop on.
  func setWorkDayStart(_ time: String) {
    let pair = WorkDayBounds.settingStart(time, start: draft.workDayStart, end: draft.workDayEnd)
    edit(AccountSettingsPatch(workDayStart: pair.start, workDayEnd: pair.end))
  }

  func setWorkDayEnd(_ time: String) {
    let pair = WorkDayBounds.settingEnd(time, start: draft.workDayStart, end: draft.workDayEnd)
    edit(AccountSettingsPatch(workDayStart: pair.start, workDayEnd: pair.end))
  }

  /// Turning reminders on asks iOS for permission first, as the web asks the browser.
  func setNotifications(_ enabled: Bool) async {
    notificationError = nil
    guard enabled else {
      commit(AccountSettingsPatch(notifications: false))
      return
    }
    guard let store else { return }
    if await store.requestNotificationPermission() {
      store.errorMessage = nil
      commit(AccountSettingsPatch(notifications: true))
    } else {
      store.errorMessage = nil
      notificationError = text(
        "Разреши уведомления для Ritm в настройках iPhone.",
        "Allow notifications for Ritm in iPhone Settings.")
    }
    await refreshPhonePermission()
  }

  func refreshPhonePermission() async {
    let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    switch status {
    case .authorized, .provisional, .ephemeral: phoneNotificationsAllowed = true
    case .denied: phoneNotificationsAllowed = false
    default: phoneNotificationsAllowed = nil
    }
  }

  // MARK: Sending

  /// Sends the waiting changes one request at a time. A failure puts the unsent fields back and
  /// says so; nothing is retried by itself, so an uncertain write is never repeated.
  func flush() async {
    guard !flushing, let store else { return }
    flushing = true
    defer { flushing = false }
    while let patch = state.begin() {
      await waitForStore(store)
      let saved = await store.saveSettings(patch)
      if patch.theme != nil { store.previewTheme(nil) }
      guard let saved else {
        failedToSave(store)
        return
      }
      state.succeed(saved)
      heldIssue = state.heldIssues.first
      showToast(text("Сохранено", "Saved"), failed: false)
      if Self.touchesReminders(patch) { await store.updateLocalNotifications() }
    }
  }

  private func waitForStore(_ store: RitmStore) async {
    var steps = 0
    while store.isMutating && steps < Self.waitSteps {
      try? await Task.sleep(for: Self.waitStep)
      steps += 1
    }
  }

  private func failedToSave(_ store: RitmStore) {
    state.fail()
    let reason = store.errorMessage
    showToast(
      reason ?? text("Не сохранено. Проверьте связь.", "Not saved. Check the connection."),
      failed: true)
  }

  private static func touchesReminders(_ patch: AccountSettingsPatch) -> Bool {
    patch.notifications != nil || patch.dailyBriefing != nil || patch.timeZone != nil
      || patch.language != nil || patch.workDayStart != nil || patch.workDayEnd != nil
  }

  // MARK: Toast

  func showToast(_ text: String, failed: Bool) {
    toastSerial += 1
    let mine = toastSerial
    toast = SettingsToast(id: mine, text: text, failed: failed)
    UIAccessibility.post(notification: .announcement, argument: text)
    toastTask?.cancel()
    toastTask = Task { [weak self] in
      try? await Task.sleep(for: failed ? .seconds(3.2) : Self.toastLifetime)
      guard !Task.isCancelled, let self, self.toastSerial == mine else { return }
      self.toast = nil
    }
  }
}

extension SettingsModel {
  /// A theme tap: the app switches at once, the account saves it right behind.
  func setTheme(_ theme: Theme) {
    store?.previewTheme(theme)
    commit(AccountSettingsPatch(theme: theme))
  }
}
