import Foundation

/// The bookkeeping behind «настройки сохраняются сами»: what the screen shows (`draft`), what
/// the server last confirmed (`server`), the changes waiting to be sent (`dirty`) and the ones on
/// their way (`inflight`). It sends only the fields that changed, one request at a time, and a
/// field is never overwritten by a response or a refresh while the owner has a newer value.
public struct SettingsAutosaveState: Equatable, Sendable {
  public private(set) var server: AccountSettings
  public private(set) var draft: AccountSettings
  public private(set) var dirty = AccountSettingsPatch()
  public private(set) var inflight = AccountSettingsPatch()

  public init(server: AccountSettings) {
    self.server = server
    self.draft = server
  }

  public var hasPendingChanges: Bool { !dirty.isEmpty || !inflight.isEmpty }
  public var isSending: Bool { !inflight.isEmpty }

  /// The owner changed something: the screen updates at once and the change waits to be sent.
  public mutating func edit(_ change: AccountSettingsPatch) {
    guard !change.isEmpty else { return }
    draft = change.applied(to: draft)
    dirty = dirty.overlaid(by: change)
    dropRedundantChanges()
  }

  /// Takes the next change to send, or nil when nothing can go: a request is already running,
  /// nothing changed, or every changed value is invalid (those stay held, see `revertInvalid`).
  public mutating func begin() -> AccountSettingsPatch? {
    guard inflight.isEmpty, !dirty.isEmpty else { return nil }
    let check = SettingsValidator.check(dirty, in: draft)
    let sendable = check.valid.removing(unchangedFields(of: check.valid))
    dirty = dirty.removing(check.valid.fields)
    guard !sendable.isEmpty else { return nil }
    inflight = sendable
    return sendable
  }

  /// What is wrong with the changes that are being held back, if anything.
  public var heldIssues: [SettingsIssue] { SettingsValidator.check(dirty, in: draft).issues }

  /// The server accepted `inflight` and answered with the whole settings object.
  public mutating func succeed(_ saved: AccountSettings) {
    server = saved
    inflight = AccountSettingsPatch()
    followServer()
  }

  /// The request failed: what the owner changed goes back to the confirmed values, except what
  /// was changed again meanwhile. Returns the fields that were put back.
  @discardableResult
  public mutating func fail() -> Set<SettingsField> {
    let reverted = inflight.fields.subtracting(dirty.fields)
    inflight = AccountSettingsPatch()
    restore(reverted)
    return reverted
  }

  /// A fresh copy from the server (polling): fields without a pending change follow it.
  public mutating func adopt(_ fresh: AccountSettings) {
    server = fresh
    followServer()
  }

  /// The owner left a field with a value that cannot be sent: put the confirmed value back.
  /// Returns the issues that were dropped.
  @discardableResult
  public mutating func revertInvalid() -> [SettingsIssue] {
    let check = SettingsValidator.check(dirty, in: draft)
    dirty = dirty.removing(check.invalidFields)
    restore(check.invalidFields)
    return check.issues
  }

  // MARK: Private

  private mutating func restore(_ fields: Set<SettingsField>) {
    guard !fields.isEmpty else { return }
    draft = AccountSettingsPatch.snapshot(of: server, fields: fields).applied(to: draft)
  }

  /// Every field without a pending change shows the server value; a pending change that now
  /// equals the server's is no change at all.
  private mutating func followServer() {
    let waiting = dirty.fields.union(inflight.fields)
    restore(Set(SettingsField.allCases).subtracting(waiting))
    dropRedundantChanges()
  }

  private mutating func dropRedundantChanges() {
    dirty = dirty.removing(unchangedFields(of: dirty).subtracting(inflight.fields))
  }

  private func unchangedFields(of patch: AccountSettingsPatch) -> Set<SettingsField> {
    let merged = patch.applied(to: server)
    return patch.fields.filter { field in
      AccountSettingsPatch.snapshot(of: merged, fields: [field])
        == AccountSettingsPatch.snapshot(of: server, fields: [field])
    }
  }
}
