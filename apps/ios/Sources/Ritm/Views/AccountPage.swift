import RitmCore
import SwiftUI

/// Where the theme reveal grows from: the selected theme tile when it is on screen, otherwise
/// the save button. Frames are in window coordinates and only read at the moment of saving.
@MainActor private final class SettingsRevealFrames {
  var tiles: [String: CGRect] = [:]
  var save: CGRect = .zero
}

/// A theme reveal armed by Save, started once the app really switches colour scheme.
private struct ThemeRevealRequest {
  let origin: CGPoint
  let expires: Date
}

/// Inputs that decide when the one-shot scroll to the notifications card can run.
private struct NotificationScrollTrigger: Equatable {
  let requested: Bool
  let ready: Bool
  let onSettings: Bool
}

/// «Настройки»: src/features/SettingsPage.tsx at 390 px.
struct AccountView: View {
  @Environment(RitmStore.self) private var store
  @Environment(RitmNavigation.self) private var navigation
  @Environment(\.openURL) private var openURL
  @Environment(\.colorScheme) private var scheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.ritmPageActive) private var pageActive
  @State private var draft = AccountSettings()
  @State private var baseline: AccountSettings?
  @State private var google: GoogleCalendarStatus?
  @State private var googleSetup: GoogleOAuthSetup?
  @State private var telegram: TelegramStatus?
  @State private var showingBrowser = false
  @State private var secretEditor: IntegrationKind?
  @State private var confirmation: IntegrationKind?
  @State private var loadingIntegrations = false
  @State private var notice: String?
  @State private var saveError: String?
  @State private var saved = false
  @State private var saving = false
  @State private var notificationError: String?
  @State private var revealFrames = SettingsRevealFrames()
  @State private var themeReveal: ThemeRevealRequest?
  @State private var scrollTick = 0
  private static let notificationsAnchor = "settings-notifications"

  private var dirty: Bool { baseline.map { $0 != draft } ?? false }
  private var initials: String {
    let letters = draft.displayName.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)
    return letters.isEmpty ? store.text("Р", "R") : String(letters).uppercased()
  }

  /// SettingsPage.tsx TIME_ZONES; an unlisted zone of the account stays selectable.
  private var zones: [(String, String)] {
    let list = [
      ("Asia/Qyzylorda", store.text("Кызылорда · UTC+5", "Qyzylorda · UTC+5")),
      ("Asia/Almaty", store.text("Алматы, Астана · UTC+5", "Almaty, Astana · UTC+5")),
      ("Europe/Moscow", store.text("Москва · UTC+3", "Moscow · UTC+3")),
      ("Europe/Kyiv", store.text("Киев", "Kyiv")),
      ("Europe/Minsk", store.text("Минск · UTC+3", "Minsk · UTC+3")),
      ("Asia/Tashkent", store.text("Ташкент · UTC+5", "Tashkent · UTC+5")),
      ("Asia/Bishkek", store.text("Бишкек · UTC+6", "Bishkek · UTC+6")),
      ("Europe/Berlin", store.text("Берлин", "Berlin")),
      ("Europe/London", store.text("Лондон", "London")),
      ("America/New_York", store.text("Нью-Йорк", "New York")),
      ("UTC", store.text("Всемирное время · UTC", "Coordinated Universal Time · UTC")),
    ]
    return list.contains { $0.0 == draft.timeZone } ? list : [(draft.timeZone, draft.timeZone)] + list
  }

  var body: some View {
    ZStack {
      RitmBackground()
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            RitmShellHeader()
            RitmPageHeading(title: store.text("Настройки", "Settings"))
            if let message = store.errorMessage { RitmErrorBanner(message: message).padding(.bottom, 12) }
            MutationRecoveryView()
            if baseline != nil {
              VStack(spacing: 14) {
                languageCard.ritmPageReveal(index: 0)
                accountCard.ritmPageReveal(index: 1)
                appearanceCard.ritmPageReveal(index: 2)
                notificationsCard.ritmPageReveal(index: 3).id(Self.notificationsAnchor)
                connectionsCard.ritmPageReveal(index: 4)
                WalletSettingsCard().ritmPageReveal(index: 5)
                ServerAddressCard().ritmPageReveal(index: 6)
              }
              .padding(.top, 22)
              .disabled(saving)
              saveBar
            }
            Button {
              Task { await store.signOut() }
            } label: {
              Label(store.text("Выйти из аккаунта", "Sign out"), systemImage: "rectangle.portrait.and.arrow.right")
                .ritmFont(12, weight: .medium)
                .foregroundStyle(RitmTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(RitmPressStyle(scale: 0.97))
            .disabled(store.isMutating)
            .padding(.top, 17)
            RitmPageFooter()
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 28)
          .frame(maxWidth: 700)
          .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
          await store.refresh()
          await loadIntegrations()
        }
        .task(id: scrollTrigger) { await awaitNotificationsScroll() }
        .onChange(of: scrollTick) { _, _ in
          withAnimation(reduceMotion ? nil : RitmMotion.easeInOut(0.5)) {
            proxy.scrollTo(Self.notificationsAnchor, anchor: .top)
          }
        }
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .onAppear { mergeSettings(store.bootstrap?.settings) }
    .task(id: navigation.section) {
      if navigation.section == .settings { await loadIntegrations() }
    }
    .onChange(of: store.bootstrap?.settings) { _, settings in mergeSettings(settings) }
    .onChange(of: store.lastSyncedAt) { _, _ in
      if navigation.section == .settings { Task { await loadIntegrations() } }
    }
    .onChange(of: scheme) { _, _ in startThemeReveal() }
    .onChange(of: draft) { _, _ in
      saved = false
      saveError = nil
    }
    .sheet(
      isPresented: $showingBrowser,
      onDismiss: {
        Task {
          await store.refresh()
          await loadIntegrations()
        }
      }
    ) {
      IntegrationBrowser(server: store.serverAddress, onDismiss: { showingBrowser = false })
    }
    .sheet(item: $secretEditor, onDismiss: { Task { await loadIntegrations() } }) { kind in
      IntegrationSecretEditor(kind: kind, googleSetup: googleSetup)
    }
    .confirmationDialog(
      confirmation == .google
        ? store.text("Отключить Google Calendar?", "Disconnect Google Calendar?")
        : store.text("Отключить интеграцию?", "Disconnect this integration?"),
      isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
      titleVisibility: .visible
    ) {
      if let kind = confirmation {
        Button(store.text("Отключить", "Disconnect"), role: .destructive) {
          Task { await disconnect(kind) }
        }
      }
    } message: {
      Text(
        confirmation == .google
          ? store.text(
            "Ritm перестанет получать и изменять события. События в Google и подключение другого приложения сохранятся.",
            "Ritm will stop reading and changing events. Your Google events and other apps' access stay as they are.")
          : store.text(
            "Данные на стороне сервиса сохранятся. Подключение в Ritm потребуется настроить снова.",
            "Data in the service stays intact. You will need to reconnect it in Ritm."))
    }
  }

  // MARK: Cards

  private var languageCard: some View {
    SettingsCard(symbol: "globe", title: store.text("Язык и время", "Language and time")) {
      SettingsField(label: store.text("Язык интерфейса", "Interface language")) {
        SettingsSelect(options: [(Language.ru, "Русский"), (Language.en, "English")], selection: $draft.language)
      }
      SettingsField(label: store.text("Часовой пояс", "Time zone")) {
        SettingsSelect(options: zones, selection: $draft.timeZone)
      }
      HStack(spacing: 10) {
        SettingsField(label: store.text("Начало дня", "Day starts")) {
          TimeStringPicker(title: "", value: $draft.workDayStart, zone: draft.timeZone).labelsHidden()
        }
        SettingsField(label: store.text("Конец дня", "Day ends")) {
          TimeStringPicker(title: "", value: $draft.workDayEnd, zone: draft.timeZone).labelsHidden()
        }
      }
      SettingsHint(text: store.text("Помощник учитывает эти часы при планировании.", "The assistant uses these hours when planning."))
    }
  }

  private var accountCard: some View {
    SettingsCard(symbol: "person", title: store.text("Аккаунт", "Account")) {
      HStack(spacing: 14) {
        Text(initials)
          .ritmFont(19, weight: .semibold)
          .foregroundStyle(RitmTheme.accentColor)
          .frame(width: 52, height: 52)
          .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 17, style: .circular))
          .overlay { RoundedRectangle(cornerRadius: 17, style: .circular).strokeBorder(RitmTheme.line, lineWidth: 1) }
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(draft.displayName.isEmpty ? store.text("Твоё имя", "Your name") : draft.displayName)
            .ritmFont(16, weight: .semibold)
            .foregroundStyle(RitmTheme.text)
          Text(store.text("Твой личный Ritm", "Your personal Ritm")).ritmFont(11).foregroundStyle(RitmTheme.muted)
        }
      }
      .padding(.top, 18)
      .padding(.bottom, 4)
      SettingsField(label: store.text("Имя", "Name")) {
        TextField("", text: $draft.displayName).textContentType(.name)
          .onChange(of: draft.displayName) { _, value in
            if value.count > 60 { draft.displayName = String(value.prefix(60)) }
          }
      }
      SettingsField(label: store.text("Электронная почта", "Email")) {
        TextField("", text: $draft.email, prompt: Text(store.text("Твоя почта", "Your email")).foregroundColor(RitmTheme.muted))
          .textContentType(.emailAddress)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      }
      SettingsHint(text: store.text("Для профиля. Почтовые уведомления пока не подключены.", "For your profile. Email notifications are not connected yet."))
    }
  }

  private var appearanceCard: some View {
    SettingsCard(symbol: "paintpalette", title: store.text("Оформление", "Appearance")) {
      Text(store.text("Фиолетовые оттенки в твоём любимом освещении.", "Violet tones in your favourite light."))
        .ritmFont(12)
        .foregroundStyle(RitmTheme.muted)
        .padding(.top, 16)
        .padding(.bottom, 17)
      HStack(spacing: 8) {
        themeTile(.light, key: "light", title: store.text("Светлая", "Light"), symbol: "sun.max")
        themeTile(.dark, key: "dark", title: store.text("Тёмная", "Dark"), symbol: "moon")
        themeTile(.system, key: "system", title: store.text("Системная", "System"), symbol: "sparkles")
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel(store.text("Тема приложения", "App theme"))
      SettingsField(label: store.text("Боковая панель", "Sidebar")) {
        SettingsSelect(options: [("dark", store.text("Графитовая", "Graphite")), ("light", store.text("Светлая", "Light"))], selection: $draft.sidebar)
      }
      SettingsHint(text: store.text("Новое оформление появится после сохранения.", "The new look appears after you save."))
    }
  }

  private func themeTile(_ theme: Theme, key: String, title: String, symbol: String) -> some View {
    SettingsThemeTile(theme: theme, title: title, symbol: symbol, selected: draft.theme == theme) {
      draft.theme = theme
    }
    .ritmFrameReader(active: pageActive) { revealFrames.tiles[key] = $0 }
  }

  private var notificationsCard: some View {
    SettingsCard(symbol: "bell", title: store.text("Уведомления", "Notifications")) {
      SettingsSwitchRow(
        title: store.text("Напоминания о задачах", "Task reminders"),
        note: store.text("За 15 минут до начала, пока Ritm открыт", "15 minutes before the start, while Ritm is open"),
        isOn: Binding(get: { draft.notifications }, set: { value in Task { await setNotifications(value) } }))
      Rectangle().fill(RitmTheme.line).frame(height: 1)
      SettingsSwitchRow(
        title: store.text("Утренний план", "Morning plan"),
        note: store.text("Сводка в начале рабочего дня, пока Ritm открыт", "A summary at the start of the workday, while Ritm is open"),
        isOn: $draft.dailyBriefing)
        .disabled(!draft.notifications)
      if let notificationError {
        Label(notificationError, systemImage: "exclamationmark.circle")
          .ritmFont(11, lineSpacing: 3)
          .foregroundStyle(RitmTheme.danger)
      } else {
        SettingsHint(text: store.text("Для напоминаний понадобится разрешение iPhone.", "Reminders need permission on this iPhone."))
      }
      HStack(spacing: 12) {
        Image(systemName: "moon").font(.system(size: 15)).accessibilityHidden(true)
        Text(store.text("Только полезные напоминания.\nВ твоём ритме.", "Only useful reminders.\nAt your pace."))
          .ritmFont(11, lineSpacing: 4)
      }
      .foregroundStyle(RitmTheme.muted)
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RitmTheme.soft.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .circular))
      .padding(.top, 22)
    }
  }

  private var connectionsCard: some View {
    SettingsCard(symbol: "sparkles", title: store.text("Подключения", "Connections")) {
      VStack(spacing: 0) {
        aiRow
        googleRow
        telegramRow
      }
      .padding(.top, 16)
      if let notice {
        Label(notice, systemImage: "checkmark.circle")
          .ritmFont(11, lineSpacing: 3)
          .foregroundStyle(RitmTheme.accentColor)
          .padding(.top, 8)
      }
    }
  }

  private var aiRow: some View {
    let status = store.bootstrap?.aiStatus
    let configured = status?.configured == true
    return SettingsConnectionRow(
      symbol: "sparkles", name: "OpenAI",
      status: configured
        ? store.text("Ключ настроен · ", "Key configured · ") + (status?.model ?? "")
        : store.text("Не настроен", "Not configured"),
      connected: configured,
      notes: status?.source == "environment" ? [store.text("Настройкой управляет сервер", "The server manages this setting")] : []
    ) {
      if status?.source == "environment" {
        Text(store.text("На сервере", "On the server")).ritmFont(11).foregroundStyle(RitmTheme.muted).frame(minHeight: 44)
      } else {
        SettingsSmallButton(title: configured ? store.text("Изменить", "Change") : store.text("Настроить", "Set up")) {
          secretEditor = .ai
        }
        .disabled(!store.canWrite)
      }
      if status?.source == "saved" {
        Button(store.text("Удалить ключ", "Remove key")) { confirmation = .ai }
          .buttonStyle(RitmTextButtonStyle())
          .disabled(!store.canWrite)
      }
    }
  }

  private var googleRow: some View {
    let configured = googleSetup?.configured ?? google?.configured ?? false
    let connected = google?.status == .connected
    var notes = [
      configured
        ? store.text("Основной календарь · просмотр, создание и редактирование событий", "Primary calendar · view, create and edit events")
        : store.text("Добавьте Client ID и Client Secret из Google Cloud", "Add the Client ID and Client Secret from Google Cloud")
    ]
    if connected {
      notes.append(
        google?.extendedColors == true
          ? store.text("Полная палитра включена", "The full palette is on")
          : store.text("Для новых оттенков Google попросит разрешение на управление календарями.", "For more colours Google asks permission to manage calendars."))
    }
    if google?.tasksEnabled == true {
      notes.append(store.text("Google Tasks: отметки выполнения подключены", "Google Tasks: completion marks connected"))
    }
    if let message = store.googleTasks?.message { notes.append(message) }
    return SettingsConnectionRow(
      symbol: "calendar", name: "Google Calendar", status: googleStatusText(configured: configured),
      connected: connected, notes: notes
    ) {
      SettingsSmallButton(title: configured ? store.text("Настройки", "Settings") : store.text("Настроить", "Set up")) {
        secretEditor = .google
      }
      .disabled(!store.canWrite || googleSetup?.source == "environment")
      if configured {
        // Google sign-in happens on the Ritm website in the secure browser (no native OAuth yet).
        SettingsSmallButton(
          title: connected || google?.status == .reauthRequired
            ? store.text("Переподключить", "Reconnect") : store.text("Подключить", "Connect")
        ) { showingBrowser = true }
        .disabled(!store.canWrite)
      }
      if connected && (google?.tasksEnabled != true || google?.extendedColors != true) {
        SettingsSmallButton(title: store.text("Расширить доступ", "Extend access")) { showingBrowser = true }
          .disabled(!store.canWrite)
      }
      if configured && (connected || google?.status == .reauthRequired) {
        Button(store.text("Отключить", "Disconnect")) { confirmation = .google }
          .buttonStyle(RitmTextButtonStyle())
          .disabled(!store.canWrite)
      }
    }
  }

  private func googleStatusText(configured: Bool) -> String {
    switch google?.status {
    case .connected: return store.text("Подключён", "Connected")
    case .reauthRequired: return store.text("Нужно подключить заново", "Reconnection needed")
    case .none: return store.text("Статус пока не загружен", "Status not loaded yet")
    default:
      return configured ? store.text("Не подключён", "Not connected") : store.text("Нужна настройка OAuth-клиента", "OAuth client setup needed")
    }
  }

  private var telegramNotes: [String] {
    var notes = [
      telegram?.botUsername.map { "@" + $0 }
        ?? store.text("Подключи своего бота, затем привяжи личный чат.", "Connect your bot, then link your private chat.")
    ]
    if telegram?.linked == true, let account = telegram?.account {
      notes.append(store.text("Привязан: ", "Linked: ") + (account.username.map { "@" + $0 } ?? account.firstName))
    }
    notes.append(
      store.text(
        "В личном чате отправь /menu, чтобы открыть кнопки быстрых дел, плана и итога. Сообщения не передаются ИИ.",
        "Send /menu in the private chat to open quick task, plan and summary buttons. Messages are not passed to AI."))
    return notes
  }

  @ViewBuilder private var telegramRow: some View {
    let linked = telegram?.linked == true
    let configured = telegram?.configured == true
    let notes = telegramNotes
    SettingsConnectionRow(
      symbol: "paperplane", name: "Telegram",
      status: linked
        ? store.text("Личный чат привязан", "Private chat linked")
        : configured ? store.text("Бот настроен · чат не привязан", "Bot configured · chat not linked") : store.text("Не настроен", "Not configured"),
      connected: linked, notes: notes
    ) {
      SettingsSmallButton(title: configured ? store.text("Сменить бота", "Change bot") : store.text("Настроить", "Set up")) {
        secretEditor = .telegram
      }
      .disabled(!store.canWrite)
      if configured && !linked {
        SettingsSmallButton(title: store.text("Привязать чат", "Link chat")) {
          Task { if let result = await store.write({ try await $0.pairTelegram() }) { telegram = result } }
        }
        .disabled(!store.canWrite)
      }
      if configured {
        Button(store.text("Отключить", "Disconnect")) { confirmation = .telegram }
          .buttonStyle(RitmTextButtonStyle())
          .disabled(!store.canWrite)
      }
    }
    if let url = safePairingURL, !linked {
      VStack(alignment: .leading, spacing: 8) {
        Text(store.text("Открой ссылку в Telegram и нажми Start, затем вернись сюда. Ссылка действует 10 минут.", "Open the link in Telegram and tap Start, then come back. The link is valid for 10 minutes."))
          .ritmFont(11, lineSpacing: 4)
          .foregroundStyle(RitmTheme.muted)
        HStack(spacing: 8) {
          SettingsSmallButton(title: store.text("Открыть бота в Telegram", "Open the bot in Telegram")) { openURL(url) }
          Button(store.text("Проверить подключение", "Check connection")) { Task { await loadIntegrations() } }
            .buttonStyle(RitmTextButtonStyle())
        }
      }
      .padding(.bottom, 12)
    }
    telegramReminders
  }

  private var telegramReminders: some View {
    let reminders = telegram?.reminders
    let linked = telegram?.linked == true
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(store.text("Напоминания в Telegram", "Telegram reminders")).ritmFont(12, weight: .semibold).foregroundStyle(RitmTheme.text)
          Text(
            reminders?.ready == true
              ? store.text("Автоматическая отправка работает", "Automatic delivery is working")
              : reminders?.problem.flatMap(reminderProblemText)
                ?? store.text("Ожидание планировщика или привязки чата", "Waiting for the scheduler or a linked chat")
          )
          .ritmFont(10, lineSpacing: 3)
          .foregroundStyle(RitmTheme.muted)
        }
        Spacer(minLength: 0)
        Toggle(store.text("Включить", "On"), isOn: Binding(
          get: { reminders?.enabled ?? false },
          set: { value in Task { await saveReminders(enabled: value, lead: reminders?.leadMinutes ?? 10) } }))
          .labelsHidden()
          .tint(RitmTheme.accentColor)
          .disabled(!linked || !store.canWrite)
          .accessibilityLabel(store.text("Напоминания в Telegram", "Telegram reminders"))
      }
      SettingsField(label: store.text("Предупредить", "Remind me")) {
        SettingsSelect(
          options: [0, 5, 10, 15, 30, 60].map { minutes in
            (minutes, minutes == 0 ? store.text("В момент начала", "At the start") : store.text("За \(minutes) минут", "\(minutes) minutes before"))
          },
          selection: Binding(
            get: { reminders?.leadMinutes ?? 10 },
            set: { value in Task { await saveReminders(enabled: reminders?.enabled ?? false, lead: value) } }))
      }
      .padding(.top, -16)
      .disabled(!linked || !store.canWrite)
      if linked {
        Button(store.text("Отправить тестовое уведомление", "Send a test notification")) {
          Task {
            if await store.performMutation({ try await $0.testTelegramReminder() }) {
              notice = store.text("Сервер подтвердил отправку тестового уведомления.", "The server confirmed sending the test notification.")
            }
          }
        }
        .buttonStyle(RitmTextButtonStyle())
        .disabled(!store.canWrite)
      }
    }
    .padding(15)
    .background(RitmTheme.soft.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .circular))
    .padding(.top, 4)
  }

  /// `.settings-save-bar`: the state line, then Save above Discard.
  private var saveBar: some View {
    VStack(spacing: 10) {
      Group {
        if saving {
          Label(store.text("Сохраняем…", "Saving…"), systemImage: "arrow.triangle.2.circlepath")
        } else if let saveError {
          Label(saveError, systemImage: "exclamationmark.circle").foregroundStyle(RitmTheme.danger)
        } else if dirty {
          Text(store.text("Есть несохранённые изменения", "You have unsaved changes"))
        } else if saved {
          Label(store.text("Настройки сохранены", "Settings saved"), systemImage: "checkmark.circle")
        } else {
          Label(store.text("Всё сохранено", "Everything is saved"), systemImage: "checkmark")
        }
      }
      .ritmFont(11, lineSpacing: 3)
      .foregroundStyle(RitmTheme.muted)
      .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
      Button(saving ? store.text("Сохраняем…", "Saving…") : store.text("Сохранить настройки", "Save settings")) {
        Task { await saveSettings() }
      }
      .buttonStyle(RitmPrimaryButtonStyle(minHeight: 48))
      .ritmFrameReader(active: pageActive) { revealFrames.save = $0 }
      .disabled(!dirty || saving || !store.canWrite)
      if dirty {
        Button(store.text("Отменить изменения", "Discard changes")) {
          if let value = store.bootstrap?.settings {
            draft = value
            baseline = value
          }
          saveError = nil
        }
        .buttonStyle(RitmTextButtonStyle(size: 12))
        .frame(maxWidth: .infinity)
        .disabled(saving)
      }
    }
    .padding(.top, 21)
    .padding(.bottom, 5)
  }

  // MARK: Actions

  private var safePairingURL: URL? {
    guard let raw = telegram?.pairingUrl, let url = URL(string: raw), url.scheme == "https",
      url.host == "t.me", url.user == nil, url.password == nil,
      let expires = telegram?.pairingExpiresAt, expires > Date().timeIntervalSince1970 * 1000
    else { return nil }
    return url
  }

  /// Reminder problem codes as TelegramConnection.tsx words them; unknown codes fall back.
  private func reminderProblemText(_ code: String) -> String? {
    switch code {
    case "disabled": store.text("Автоматическая отправка выключена", "Automatic delivery is off")
    case "chat_unlinked": store.text("Личный чат Telegram не привязан.", "The private Telegram chat is not linked.")
    case "scheduler_unconfigured": store.text("Серверные ключи планировщика не настроены.", "The scheduler server keys are not configured.")
    case "scheduler_waiting": store.text("Ожидается первый автоматический запуск планировщика.", "Waiting for the first automatic scheduler run.")
    case "scheduler_stale": store.text("Планировщик не запускался более пяти минут.", "The scheduler has not run for over five minutes.")
    case "google_disconnected": store.text("Google Calendar не подключён.", "Google Calendar is not connected.")
    case "google_error": store.text("Не удалось проверить Google Calendar.", "Could not check Google Calendar.")
    case "telegram_error": store.text("Ошибка отправки в Telegram.", "Could not send the Telegram notification.")
    case "telegram_rejected": store.text("Telegram отклонил уведомление.", "Telegram rejected the notification.")
    case "telegram_uncertain": store.text("Результат отправки в Telegram неизвестен.", "Telegram delivery status is unknown.")
    case "internal_error": store.text("Ошибка проверки напоминаний на сервере.", "The server could not check reminders.")
    default: nil
    }
  }

  /// Turning reminders on asks iOS for permission first, as the web asks the browser.
  private func setNotifications(_ enabled: Bool) async {
    notificationError = nil
    guard enabled else {
      draft.notifications = false
      return
    }
    if await store.requestNotificationPermission() {
      draft.notifications = true
    } else {
      store.errorMessage = nil
      notificationError = store.text(
        "Разреши уведомления для Ritm в настройках iPhone.", "Allow notifications for Ritm in iPhone Settings.")
    }
  }

  private func saveReminders(enabled: Bool, lead: Int) async {
    if let result = await store.write({ try await $0.saveTelegramReminders(enabled: enabled, leadMinutes: lead) }) {
      telegram = result
    }
  }

  private func loadIntegrations() async {
    guard !loadingIntegrations, store.isSignedIn, navigation.section == .settings else { return }
    loadingIntegrations = true
    defer { loadingIntegrations = false }
    if let result = await store.read({ try await $0.googleStatus() }) { google = result }
    if let result = await store.read({ try await $0.googleConfiguration() }) { googleSetup = result }
    if let result = await store.read({ try await $0.telegramStatus() }) { telegram = result }
  }

  private func saveSettings() async {
    guard dirty, !saving else { return }
    if draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      saveError = store.text("Введи имя, которым к тебе будет обращаться помощник.", "Enter the name the assistant should use for you.")
      return
    }
    if (TaskSchedule.timeMinutes(draft.workDayEnd) ?? 0) <= (TaskSchedule.timeMinutes(draft.workDayStart) ?? 1440) {
      saveError = store.text("Конец рабочего дня должен быть позже начала.", "The workday must end after it starts.")
      return
    }
    var value = draft
    value.displayName = value.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    value.email = value.email.trimmingCharacters(in: .whitespacesAndNewlines)
    saving = true
    defer { saving = false }
    armThemeReveal(for: value.theme)
    if let result = await store.saveSettings(value) {
      baseline = result
      draft = result
      saved = true
      await store.updateLocalNotifications()
    } else {
      themeReveal = nil
      if let message = store.errorMessage { saveError = message }
    }
  }

  // MARK: Theme reveal

  /// Saving a different effective theme switches the whole app, so it gets the same circular
  /// reveal as the top-bar toggle. The snapshot of the old look is taken when the scheme
  /// actually changes (`startThemeReveal`), which is after the server accepted the save.
  private func armThemeReveal(for theme: Theme) {
    let toDark = theme == .system ? RitmThemeReveal.systemIsDark : theme == .dark
    guard toDark != (scheme == .dark) else {
      themeReveal = nil
      return
    }
    let bounds = RitmThemeReveal.windowBounds
    let tile = revealFrames.tiles[theme.rawValue]
    let anchor = tile.flatMap { bounds.contains($0) ? $0 : nil } ?? revealFrames.save
    let origin = anchor == .zero ? CGPoint(x: bounds.midX, y: bounds.maxY - 120) : CGPoint(x: anchor.midX, y: anchor.midY)
    themeReveal = ThemeRevealRequest(origin: origin, expires: Date().addingTimeInterval(10))
  }

  private func startThemeReveal() {
    guard let request = themeReveal else { return }
    themeReveal = nil
    guard request.expires > Date() else { return }
    RitmThemeReveal.run(origin: request.origin, reduceMotion: reduceMotion) {}
  }

  // MARK: Scroll to notifications

  private var scrollTrigger: NotificationScrollTrigger {
    NotificationScrollTrigger(
      requested: navigation.scrollToNotifications, ready: baseline != nil,
      onSettings: navigation.section == .settings)
  }

  /// «Настройки уведомлений» in the bell popover: once the page is shown and its cards exist,
  /// wait for the reveal to lay out, then scroll once.
  private func awaitNotificationsScroll() async {
    let trigger = scrollTrigger
    guard trigger.requested, trigger.ready, trigger.onSettings else { return }
    try? await Task.sleep(for: .milliseconds(350))
    guard !Task.isCancelled, navigation.scrollToNotifications else { return }
    navigation.scrollToNotifications = false
    scrollTick += 1
  }

  private func disconnect(_ kind: IntegrationKind) async {
    confirmation = nil
    switch kind {
    case .google:
      if let result = await store.write({ try await $0.disconnectGoogle() }) {
        google = result
        notice = store.text("Google Calendar отключён от Ritm.", "Google Calendar is disconnected from Ritm.")
      }
    case .ai:
      if await store.write({ try await $0.disconnectAI() }) != nil {
        notice = store.text("Сохранённый ключ удалён.", "The saved key was removed.")
      }
    case .telegram:
      if let result = await store.write({ try await $0.disconnectTelegram() }) { telegram = result }
    }
    await loadIntegrations()
  }

  /// A polling response only replaces untouched fields; typing is never reset by refresh.
  private func mergeSettings(_ fresh: AccountSettings?) {
    guard let fresh else { return }
    guard let old = baseline else {
      draft = fresh
      baseline = fresh
      return
    }
    if draft.displayName == old.displayName { draft.displayName = fresh.displayName }
    if draft.email == old.email { draft.email = fresh.email }
    if draft.theme == old.theme { draft.theme = fresh.theme }
    if draft.sidebar == old.sidebar { draft.sidebar = fresh.sidebar }
    if draft.language == old.language { draft.language = fresh.language }
    if draft.timeZone == old.timeZone { draft.timeZone = fresh.timeZone }
    if draft.notifications == old.notifications { draft.notifications = fresh.notifications }
    if draft.dailyBriefing == old.dailyBriefing { draft.dailyBriefing = fresh.dailyBriefing }
    if draft.workDayStart == old.workDayStart { draft.workDayStart = fresh.workDayStart }
    if draft.workDayEnd == old.workDayEnd { draft.workDayEnd = fresh.workDayEnd }
    baseline = fresh
  }
}
