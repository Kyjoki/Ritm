import RitmCore
import SwiftUI

/// The groups of the settings list (phone-a.html `VARIANT.html`): the profile row, the basics
/// with the appearance switch, notifications, connections, «Этот iPhone» and finance.
struct SettingsMainList: View {
  let onTheme: (Theme) -> Void
  let themeFrame: (String, CGRect) -> Void
  let notificationsAnchor: String
  @Environment(RitmStore.self) private var store
  @Environment(SettingsModel.self) private var model
  @Environment(\.openURL) private var openURL

  private var language: Language { model.language }
  private var draft: AccountSettings { model.draft }

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      profile.ritmPageReveal(index: 0)
      basics.ritmPageReveal(index: 1)
      notifications.id(notificationsAnchor).ritmPageReveal(index: 2)
      connections.ritmPageReveal(index: 3)
      thisPhone.ritmPageReveal(index: 4)
      finance.ritmPageReveal(index: 5)
    }
  }

  // MARK: Profile

  /// `.a-prof`: a 54 pt avatar, the name, the email, a chevron.
  private var profile: some View {
    SettingsGroup {
      NavigationLink(value: SettingsRoute.profile) {
        HStack(spacing: 14) {
          SettingsAvatar(name: draft.displayName, size: 54)
          VStack(alignment: .leading, spacing: 0) {
            Text(draft.displayName.isEmpty ? model.text("Твоё имя", "Your name") : draft.displayName)
              .ritmFont(17, weight: .bold, tracking: -0.03)
              .foregroundStyle(RitmTheme.text)
            Text(draft.email.isEmpty ? model.text("Добавь почту", "Add an email") : draft.email)
              .ritmFont(13)
              .foregroundStyle(RitmTheme.muted)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          RitmSymbol("chevron.right").font(.system(size: 18))
            .foregroundStyle(RitmTheme.muted.opacity(0.7)).accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
      }
      .buttonStyle(SettingsRowButtonStyle())
      .accessibilityLabel(
        model.text("Профиль", "Profile") + ", " + draft.displayName)
    }
  }

  // MARK: Basics

  private var basics: some View {
    SettingsGroup {
      SettingsMenuRow(
        icon: "character.bubble", title: model.text("Язык", "Language"),
        options: [(Language.ru, "Русский"), (Language.en, "English")],
        selection: Binding(
          get: { draft.language }, set: { model.commit(AccountSettingsPatch(language: $0)) }))
      SettingsNavRow(route: .timeZone, icon: "globe", title: model.text("Часовой пояс", "Time zone")) {
        SettingsValue(
          SettingsTimeZones.rowValue(draft.timeZone, language: language, at: Date()))
      }
      SettingsNavRow(route: .workDay, icon: "clock", title: model.text("Границы дня", "Day bounds")) {
        SettingsValue(SettingsSummary.dayRange(start: draft.workDayStart, end: draft.workDayEnd))
      }
      appearance
    }
  }

  /// `aTheme`: the row with the three-icon segment.
  private var appearance: some View {
    SettingsListRow(icon: "moon", title: model.text("Оформление", "Appearance")) {
      SettingsThemeSegment(
        selection: draft.theme, label: model.text("Оформление", "Appearance"),
        title: { SettingsSummary.themeName($0, language) }, onPick: onTheme,
        onFrame: themeFrame)
    }
  }

  // MARK: Notifications

  private var notifications: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsCaption(text: model.text("Уведомления", "Notifications"))
      SettingsGroup {
        SettingsToggleRow(
          icon: "bell", title: model.text("Напоминания о задачах", "Task reminders"),
          isOn: Binding(
            get: { draft.notifications }, set: { value in Task { await model.setNotifications(value) } }))
        SettingsToggleRow(
          icon: "sunrise", title: model.text("Утренний план", "Morning plan"),
          isOn: Binding(
            get: { draft.dailyBriefing },
            set: { model.commit(AccountSettingsPatch(dailyBriefing: $0)) })
        )
        .disabled(!draft.notifications)
        SettingsActionRow(
          icon: "iphone", title: model.text("Уведомления iPhone", "iPhone notifications"),
          action: openPhoneNotifications
        ) {
          SettingsValue(SettingsSummary.phonePermission(granted: model.phoneNotificationsAllowed, language))
        }
      }
      if let error = model.notificationError {
        SettingsFootnote(text: error, tone: .error)
      } else if model.phoneNotificationsAllowed != true {
        SettingsFootnote(
          text: model.text(
            "Для напоминаний понадобится разрешение iPhone.", "Reminders need permission on this iPhone."))
      }
    }
  }

  /// Not asked yet: ask. Asked: only iPhone Settings can change the answer.
  private func openPhoneNotifications() {
    guard model.phoneNotificationsAllowed != nil else {
      Task { _ = await store.requestNotificationPermission(); await model.refreshPhonePermission() }
      return
    }
    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
  }

  // MARK: Connections

  private var connections: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsCaption(text: model.text("Подключения", "Connections"))
      SettingsGroup {
        SettingsNavRow(route: .google, icon: "calendar", title: "Google") {
          SettingsValue(SettingsSummary.google(status: model.google, setup: model.googleSetup, language))
        }
        SettingsNavRow(route: .telegram, icon: "paperplane", title: "Telegram") {
          SettingsValue(SettingsSummary.telegram(model.telegram, language))
        }
        SettingsNavRow(route: .openAI, icon: "sparkles", title: "OpenAI") {
          SettingsValue(SettingsSummary.openAI(store.bootstrap?.aiStatus, language))
        }
      }
    }
  }

  // MARK: This iPhone

  private var thisPhone: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsCaption(text: model.text("Этот iPhone", "This iPhone"))
      SettingsGroup {
        if !store.security.unavailable {
          SettingsNavRow(route: .security, icon: "shield", title: model.text("Безопасность", "Security")) {
            if let value = SettingsSummary.security(
              totpEnabled: store.security.overview?.totpEnabled, language)
            {
              SettingsValue(value)
            }
          }
        }
        SettingsNavRow(route: .health, icon: "heart", title: model.text("Apple Здоровье", "Apple Health")) {
          SettingsValue(healthSummary)
        }
        SettingsNavRow(
          route: .liveActivity, icon: "dot.radiowaves.left.and.right", title: "Live Activity"
        ) {
          SettingsValue(liveSummary)
        }
        SettingsNavRow(route: .widgets, icon: "square.grid.2x2", title: model.text("Виджеты", "Widgets"))
        SettingsNavRow(route: .server, icon: "network", title: model.text("Адрес сервера", "Server address"))
      }
    }
  }

  private var healthSummary: SettingsTrailing {
    let health = store.health
    switch health.shareStatus {
    case .allowed:
      return health.saveToHealth
        ? SettingsTrailing(model.text("Включено", "On"), .ok)
        : SettingsTrailing(model.text("Выключено", "Off"))
    case .notDetermined: return SettingsTrailing(model.text("Не подключено", "Not connected"))
    case .denied: return SettingsTrailing(model.text("Нет доступа", "No access"), .warn)
    case .unavailable: return SettingsTrailing(model.text("Недоступно", "Unavailable"))
    }
  }

  private var liveSummary: SettingsTrailing {
    store.workouts.alerts.settings.showsLiveActivity
      ? SettingsTrailing(model.text("Включена", "On"), .ok)
      : SettingsTrailing(model.text("Выключена", "Off"))
  }

  // MARK: Finance

  private var finance: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsCaption(text: model.text("Финансы", "Finance"))
      SettingsGroup {
        SettingsNavRow(route: .wallet, icon: "wallet.pass", title: model.text("Покупки из Wallet", "Wallet purchases")) {
          SettingsValue(walletSummary)
        }
        SettingsNavRow(route: .accounts, icon: "creditcard", title: model.text("Счета и карты", "Accounts and cards")) {
          if store.financeLoaded {
            SettingsValue("\(FinanceWallet.cards(store.financeEntries, today: store.today).count)")
          }
        }
      }
    }
  }

  private var walletSummary: SettingsTrailing {
    switch store.walletFolder.status {
    case .ready: SettingsTrailing(model.text("Настроено", "Set up"), .ok)
    case .notChosen: SettingsTrailing(model.text("Не настроено", "Not set up"))
    case .downloading: SettingsTrailing(model.text("Загрузка", "Downloading"))
    case .fileMissing, .needsRepick, .failed:
      SettingsTrailing(model.text("Нужна настройка", "Needs setup"), .warn)
    }
  }
}

/// The round avatar with the first letter of the name (`.av`).
struct SettingsAvatar: View {
  let name: String
  var size: CGFloat = 52

  var body: some View {
    Text(String(name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "·"))
      .ritmFont(size * 0.4, weight: .bold, tracking: -0.02)
      .foregroundStyle(RitmTheme.accentColor)
      .frame(width: size, height: size)
      .background(RitmTheme.soft, in: Circle())
      .overlay { Circle().strokeBorder(RitmTheme.accentColor.opacity(0.22), lineWidth: 1) }
      .accessibilityHidden(true)
  }
}

/// `.mini-seg`: three icon buttons in a small capsule. The look is 34 × 28; every button has a
/// 40 × 44 pt hit area.
struct SettingsThemeSegment: View {
  let selection: Theme
  let label: String
  let title: (Theme) -> String
  let onPick: (Theme) -> Void
  let onFrame: (String, CGRect) -> Void
  @Environment(\.ritmPageActive) private var pageActive
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 2) {
      ForEach(Theme.allCases, id: \.self) { theme in button(theme) }
    }
    .padding(2)
    .background(RitmTheme.soft.opacity(0.7), in: Capsule())
    .overlay { Capsule().strokeBorder(RitmTheme.line, lineWidth: 1) }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label)
  }

  private func button(_ theme: Theme) -> some View {
    let selected = theme == selection
    return Button {
      onPick(theme)
    } label: {
      icon(theme)
        .font(.system(size: 17))
        .foregroundStyle(selected ? RitmTheme.accentColor : RitmTheme.muted)
        .frame(width: 34, height: 28)
        .background {
          if selected { Capsule().fill(RitmTheme.glassRaised).shadow(color: RitmTheme.panelShadow, radius: 4, y: 2) }
        }
        .animation(reduceMotion ? nil : RitmMotion.easeOut(0.2), value: selected)
        .frame(width: 38, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(RitmPressStyle())
    .ritmFrameReader(active: pageActive) { onFrame(theme.rawValue, $0) }
    .accessibilityLabel(title(theme))
    .accessibilityAddTraits(selected ? .isSelected : [])
    .sensoryFeedback(.selection, trigger: selected)
  }

  @ViewBuilder private func icon(_ theme: Theme) -> some View {
    switch theme {
    case .light: RitmIcon(.sun)
    case .dark: RitmIcon(.moon)
    case .system: RitmIcon(.half)
    }
  }
}
