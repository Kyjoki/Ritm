import RitmCore
import SwiftUI

/// «Безопасность»: second-factor status and the devices signed in to this account. Setting up the
/// code is done on the website. Hidden when the server has no security endpoints (older server).
struct SecurityCard: View {
  @Environment(RitmStore.self) private var store
  @State private var confirmingOthers = false

  private var security: SecurityStore { store.security }

  var body: some View {
    if !security.unavailable, let overview = security.overview {
      SettingsCard(symbol: "lock.shield", title: store.text("Безопасность", "Security")) {
        SettingsConnectionRow(
          symbol: "lock.shield", name: store.text("Вход с кодом", "Sign-in code"),
          status: overview.totpEnabled
            ? store.text("Включён", "On") : store.text("Выключен", "Off"),
          connected: overview.totpEnabled,
          notes: twoFactorNotes(overview), actions: {})
        ForEach(overview.sessions) { session in deviceRow(session) }
        if let message = security.message {
          Label { Text(message) } icon: { RitmSymbol("exclamationmark.circle") }
            .ritmFont(11, lineSpacing: 3.5)
            .foregroundStyle(RitmTheme.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
        }
        if !overview.otherSessions.isEmpty {
          Button(store.text("Выйти на всех других устройствах", "Sign out on all other devices")) {
            confirmingOthers = true
          }
          .buttonStyle(SettingsTextButtonStyle(size: 11))
          .disabled(security.busy)
          .padding(.top, 8)
        }
      }
      .confirmationDialog(
        store.text("Выйти на всех других устройствах?", "Sign out on all other devices?"),
        isPresented: $confirmingOthers, titleVisibility: .visible
      ) {
        Button(store.text("Выйти на других", "Sign out others"), role: .destructive) {
          Task { await security.revokeOthers(using: store) }
        }
      } message: {
        Text(
          store.text(
            "Это устройство останется в аккаунте. На остальных потребуется войти заново.",
            "This device stays signed in. The others will have to sign in again."))
      }
    }
  }

  private func twoFactorNotes(_ overview: SecurityOverview) -> [String] {
    guard overview.totpEnabled else {
      return [
        store.text(
          "Включите вход с кодом на сайте в Настройки → Безопасность",
          "Turn on sign-in with a code on the website in Settings → Security")
      ]
    }
    return [
      store.text(
        "Кодов восстановления осталось: \(overview.recoveryCodesLeft)",
        "Recovery codes left: \(overview.recoveryCodesLeft)")
    ]
  }

  private func deviceRow(_ session: SecuritySession) -> some View {
    let isPhone = session.client == "ios"
    let kind = isPhone ? store.text("Приложение", "App") : store.text("Сайт", "Website")
    let name =
      session.deviceName ?? (isPhone ? "iPhone" : store.text("Браузер", "Browser"))
    return SettingsConnectionRow(
      symbol: isPhone ? "iphone" : "laptopcomputer", name: name,
      status: session.current
        ? store.text("Это устройство", "This device") : lastSeenText(session),
      connected: session.current, notes: [kind]
    ) {
      if !session.current {
        SettingsSmallButton(title: store.text("Выйти", "Sign out")) {
          Task { await security.revoke(sessionID: session.id, using: store) }
        }
        .disabled(security.busy)
      }
    }
  }

  private func lastSeenText(_ session: SecuritySession) -> String {
    guard let seen = session.lastSeenAt else { return store.text("Давно не заходили", "Not seen lately") }
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: store.language == .ru ? "ru_RU" : "en_US")
    formatter.unitsStyle = .short
    let when = formatter.localizedString(for: seen, relativeTo: Date())
    return store.text("Был в сети: \(when)", "Last seen: \(when)")
  }
}
