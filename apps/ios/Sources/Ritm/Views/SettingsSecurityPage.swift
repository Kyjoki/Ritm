import RitmCore
import SwiftUI

/// «Безопасность»: the second-factor status and the devices signed in to this account. Setting up
/// the code is done on the website. The row that opens this page is hidden when the server has no
/// security endpoints (an older server).
struct SettingsSecurityPage: View {
  @Environment(RitmStore.self) private var store
  @State private var confirmingOthers = false

  private var security: SecurityStore { store.security }

  var body: some View {
    SettingsPage(title: store.text("Безопасность", "Security")) {
      if let overview = security.overview {
        SettingsStatusHeader(
          title: overview.totpEnabled
            ? store.text("Вход с кодом включён", "Sign-in code is on")
            : store.text("Вход с кодом выключен", "Sign-in code is off"),
          detail: twoFactorNote(overview), tone: overview.totpEnabled ? .ok : .warn)
        SettingsCaption(text: store.text("Активные сеансы", "Active sessions"))
        SettingsGroup {
          ForEach(overview.sessions) { session in deviceRow(session) }
        }
        if let message = security.message { SettingsFootnote(text: message, tone: .error) }
        if !overview.otherSessions.isEmpty {
          SettingsButtonStack {
            SettingsActionButton(
              title: store.text("Выйти на всех других устройствах", "Sign out on all other devices"),
              kind: .danger
            ) { confirmingOthers = true }
            .disabled(security.busy)
          }
        }
      } else {
        HStack(spacing: 9) {
          ProgressView().tint(RitmTheme.accentColor)
          Text(store.text("Загружаем…", "Loading…"))
        }
        .ritmFont(12).foregroundStyle(RitmTheme.muted)
        .frame(maxWidth: .infinity, minHeight: 100)
      }
    }
    .task { await security.load(using: store) }
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

  private func twoFactorNote(_ overview: SecurityOverview) -> String {
    guard overview.totpEnabled else {
      return store.text(
        "Включите вход с кодом на сайте в Настройки → Безопасность",
        "Turn on sign-in with a code on the website in Settings → Security")
    }
    return store.text(
      "Кодов восстановления осталось: \(overview.recoveryCodesLeft)",
      "Recovery codes left: \(overview.recoveryCodesLeft)")
  }

  /// `.sess`: the device, where and when, and «Завершить» for every device but this one.
  private func deviceRow(_ session: SecuritySession) -> some View {
    let isPhone = session.client == "ios"
    let kind = isPhone ? store.text("Приложение", "App") : store.text("Сайт", "Website")
    let name = session.deviceName ?? (isPhone ? "iPhone" : store.text("Браузер", "Browser"))
    let seen = session.current ? store.text("Это устройство", "This device") : lastSeenText(session)
    return SettingsListRow(
      icon: isPhone ? "iphone" : "laptopcomputer", title: name, subtitle: "\(kind) · \(seen)"
    ) {
      if session.current {
        Text(store.text("Этот", "This"))
          .ritmFont(11, weight: .bold)
          .foregroundStyle(RitmTheme.accentColor)
          .padding(.horizontal, 9).padding(.vertical, 3)
          .background(RitmTheme.soft, in: Capsule())
      } else {
        Button {
          Task { await security.revoke(sessionID: session.id, using: store) }
        } label: {
          Text(store.text("Завершить", "End"))
            .ritmFont(13, weight: .bold)
            .foregroundStyle(RitmTheme.danger)
            .padding(.horizontal, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RitmPressStyle())
        .disabled(security.busy)
      }
    }
    .accessibilityElement(children: .contain)
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
