import RitmCore
import SwiftUI

struct AccountView: View {
  @Environment(RitmStore.self) private var store
  @Environment(RitmNavigation.self) private var navigation
  @Environment(\.openURL) private var openURL
  @AppStorage("ritm.appearance") private var appearance = "system"
  @State private var draft = AccountSettings()
  @State private var baseline: AccountSettings?
  @State private var google: GoogleCalendarStatus?
  @State private var googleSetup: GoogleOAuthSetup?
  @State private var telegram: TelegramStatus?
  @State private var reminderEnabled = false
  @State private var reminderLead = 15
  @State private var reminderDirty = false
  @State private var showingBrowser = false
  @State private var secretEditor: IntegrationKind?
  @State private var confirmation: IntegrationKind?
  @State private var confirmingLogout = false
  @State private var loadingIntegrations = false
  @State private var notice: String?
  private var dirty: Bool { baseline.map { $0 != draft } ?? false }
  private var valid: Bool {
    let name = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let email = draft.email.trimmingCharacters(in: .whitespacesAndNewlines)
    return !name.isEmpty && name.utf16.count <= 60 && email.utf16.count <= 254
      && (email.isEmpty
        || email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil)
      && (TaskSchedule.timeMinutes(draft.workDayEnd) ?? 0)
        > (TaskSchedule.timeMinutes(draft.workDayStart) ?? 1440)
      && TimeZone(identifier: draft.timeZone) != nil
  }
  private var zones: [String] {
    Array(
      Set([
        draft.timeZone, "Asia/Qyzylorda", "Asia/Almaty", "Europe/Moscow", "Europe/Kyiv",
        "Europe/Minsk", "Asia/Tashkent", "Asia/Bishkek", "Europe/Berlin", "Europe/London",
        "America/New_York", "UTC",
      ])
    ).sorted()
  }
  var body: some View {
    ZStack {
      RitmBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text(store.text("Настройки", "Settings")).font(.largeTitle.bold())
          Text(
            store.text(
              "Ваш Ritm, привычный на каждом устройстве.", "Your Ritm, familiar on every device.")
          ).font(.subheadline).foregroundStyle(.secondary)
          SyncStatusView()
          if let message = store.errorMessage { RitmErrorBanner(message: message) }
          if let notice {
            Text(notice).font(.subheadline).foregroundStyle(.tint).padding(.vertical, 6)
          }
          MutationRecoveryView()
          if baseline != nil {
            profileCard
            appearanceCard
            workdayCard
            notificationsCard
            saveControls
          }
          integrations
          syncCard
        }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 28).frame(maxWidth: 700)
          .frame(maxWidth: .infinity)
      }.scrollDismissesKeyboard(.interactively).refreshable {
        await store.refresh()
        await loadIntegrations()
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
    .sheet(
      isPresented: $showingBrowser,
      onDismiss: {
        Task {
          await store.refresh()
          await loadIntegrations()
        }
      }
    ) {
      IntegrationBrowser(onDismiss: { showingBrowser = false })
    }
    .sheet(item: $secretEditor, onDismiss: { Task { await loadIntegrations() } }) { kind in
      IntegrationSecretEditor(kind: kind, googleSetup: googleSetup)
    }
    .confirmationDialog(
      store.text("Отключить интеграцию?", "Disconnect this integration?"),
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
        store.text(
          "Данные на стороне сервиса сохранятся. Подключение в Ritm потребуется настроить снова.",
          "Data in the service stays intact. You will need to reconnect it in Ritm."))
    }
    .confirmationDialog(
      store.text("Выйти на этом устройстве?", "Sign out on this device?"),
      isPresented: $confirmingLogout, titleVisibility: .visible
    ) {
      Button(store.text("Выйти", "Sign out"), role: .destructive) { Task { await store.signOut() } }
    } message: {
      Text(
        store.text(
          "Ваши данные останутся на сервере. Локальная сессия будет удалена.",
          "Your data stays on the server. This local session will be removed."))
    }
  }
  private var profileCard: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 16) {
        Label(store.text("Профиль", "Profile"), systemImage: "person.crop.circle").font(.headline)
        VStack(alignment: .leading, spacing: 6) {
          Text(store.text("Имя", "Name")).font(.caption).foregroundStyle(.secondary)
          TextField(store.text("Ваше имя", "Your name"), text: $draft.displayName).textContentType(
            .name
          ).textFieldStyle(.roundedBorder)
        }
        VStack(alignment: .leading, spacing: 6) {
          Text("Email").font(.caption).foregroundStyle(.secondary)
          TextField("Email", text: $draft.email).textContentType(.emailAddress).keyboardType(
            .emailAddress
          ).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(
            .roundedBorder)
        }
        Picker(store.text("Язык", "Language"), selection: $draft.language) {
          Text("Русский").tag(Language.ru)
          Text("English").tag(Language.en)
        }.frame(minHeight: 44)
        Picker(store.text("Часовой пояс", "Time zone"), selection: $draft.timeZone) {
          ForEach(zones, id: \.self) { Text($0).tag($0) }
        }.frame(minHeight: 44)
      }
    }
  }
  private var appearanceCard: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 14) {
        Label(store.text("Оформление", "Appearance"), systemImage: "circle.lefthalf.filled").font(
          .headline)
        Picker(store.text("Тема аккаунта", "Account theme"), selection: $draft.theme) {
          Text(store.text("Система", "System")).tag(Theme.system)
          Text(store.text("Светлая", "Light")).tag(Theme.light)
          Text(store.text("Тёмная", "Dark")).tag(Theme.dark)
        }.pickerStyle(.segmented)
        Picker(store.text("На этом iPhone", "On this iPhone"), selection: $appearance) {
          Text(store.text("Как в системе", "System")).tag("system")
          Text(store.text("Светлая", "Light")).tag("light")
          Text(store.text("Тёмная", "Dark")).tag("dark")
        }.frame(minHeight: 44)
        Picker(store.text("Боковая панель веб-версии", "Web sidebar"), selection: $draft.sidebar) {
          Text(store.text("Графитовая", "Graphite")).tag("dark")
          Text(store.text("Светлая", "Light")).tag("light")
        }.frame(minHeight: 44)
        Text(
          store.text(
            "Тема аккаунта синхронизируется. Оформление этого iPhone можно выбрать отдельно.",
            "The account theme syncs. This iPhone can use a separate appearance.")
        ).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  private var workdayCard: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 14) {
        Label(store.text("Рабочий день", "Workday"), systemImage: "clock").font(.headline)
        TimeStringPicker(
          title: store.text("Начало", "Start"), value: $draft.workDayStart, zone: draft.timeZone)
        TimeStringPicker(
          title: store.text("Окончание", "End"), value: $draft.workDayEnd, zone: draft.timeZone)
        Text(
          store.text(
            "Помощник и свободное время учитывают эти часы и часовой пояс аккаунта.",
            "Your assistant and free time use these hours and your account time zone.")
        ).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  private var notificationsCard: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 14) {
        Label(store.text("Уведомления", "Notifications"), systemImage: "bell").font(.headline)
        Toggle(store.text("Напоминания о событиях", "Event reminders"), isOn: $draft.notifications)
        Toggle(store.text("Утренний обзор", "Morning briefing"), isOn: $draft.dailyBriefing)
          .disabled(!draft.notifications)
        Button(
          store.text("Разрешить уведомления на этом iPhone", "Allow notifications on this iPhone")
        ) {
          Task {
            let granted = await store.requestNotificationPermission()
            notice =
              granted
              ? store.text("Уведомления разрешены.", "Notifications are allowed.")
              : store.text(
                "Разрешение не получено. Откройте настройки iPhone → Ritm → Уведомления.",
                "Permission was not granted. Open iPhone Settings → Ritm → Notifications.")
            if granted { await store.updateLocalNotifications() }
          }
        }.frame(minHeight: 44)
        Text(
          store.text(
            "При сохранении включённых уведомлений iOS запросит разрешение. Локальные напоминания строятся по последним синхронизированным данным; изменения с других устройств появятся после обновления приложения.",
            "When saving enabled notifications, iOS requests permission. Local reminders use the most recently synced data; changes from other devices appear after refreshing the app."
          )
        ).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  private var saveControls: some View {
    VStack(spacing: 8) {
      if dirty {
        Text(store.text("Есть несохранённые изменения", "You have unsaved changes")).font(.caption)
          .foregroundStyle(.secondary)
      }
      if dirty && !valid {
        Text(
          store.text(
            "Проверьте имя, email и часы рабочего дня: окончание должно быть позже начала.",
            "Check your name, email and workday hours: the end must follow the start.")
        ).font(.caption).foregroundStyle(.red)
      }
      Button {
        Task { await saveSettings() }
      } label: {
        Text(store.text("Сохранить настройки", "Save settings"))
      }.buttonStyle(RitmPrimaryButtonStyle()).disabled(!dirty || !valid || !store.canWrite)
      if dirty {
        Button(store.text("Отменить изменения", "Discard changes")) {
          if let value = store.bootstrap?.settings {
            draft = value
            baseline = value
          }
        }.frame(minHeight: 44)
      }
    }
  }
  private var integrations: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text(store.text("Интеграции", "Integrations")).font(.title2.bold())
        Spacer()
        if loadingIntegrations { ProgressView() }
      }
      googleCard
      aiCard
      telegramCard
    }
  }
  private var googleCard: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 14) {
        Label("Google Calendar", systemImage: "calendar").font(.headline)
        Text(googleLabel).font(.subheadline).foregroundStyle(.secondary)
        if let google {
          LabeledContent(
            store.text("Дополнительные цвета", "Extended colors"),
            value: google.extendedColors == true
              ? store.text("Разрешены", "Allowed") : store.text("Не разрешены", "Not allowed")
          ).font(.caption)
          LabeledContent(
            "Google Tasks",
            value: google.tasksEnabled == true
              ? store.text("Подключён", "Connected") : store.text("Не подключён", "Not connected")
          ).font(.caption)
        }
        Button {
          showingBrowser = true
        } label: {
          Label(
            store.text("Подключить или изменить доступ Google", "Connect or change Google access"),
            systemImage: "arrow.up.right.square"
          ).frame(minHeight: 44)
        }.disabled(!store.canWrite)
        Text(
          store.text(
            "Откроются настройки Ritm в безопасном браузере. Войдите при необходимости, подключите Google или расширьте доступ к цветам и Tasks. После «Готово» данные обновятся здесь.",
            "Ritm settings open in the secure browser. Sign in if needed, connect Google or extend color and Tasks permissions. Tap Done to refresh here."
          )
        ).font(.caption).foregroundStyle(.secondary)
        if googleSetup?.source != "environment" {
          Button(store.text("Настройка OAuth приложения", "OAuth app configuration")) {
            secretEditor = .google
          }.frame(minHeight: 44).disabled(!store.canWrite)
        }
        if google?.status == .connected || google?.status == .reauthRequired {
          Button(store.text("Отключить Google", "Disconnect Google"), role: .destructive) {
            confirmation = .google
          }.frame(minHeight: 44).disabled(!store.canWrite)
        }
      }
    }
  }
  private var aiCard: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 14) {
        Label(store.text("ИИ-помощник", "AI assistant"), systemImage: "sparkles").font(.headline)
        let status = store.bootstrap?.aiStatus
        Text(
          status?.configured == true
            ? store.text("Подключён · ", "Connected · ") + (status?.model ?? "")
            : store.text("Модель не подключена", "No model connected")
        ).font(.subheadline).foregroundStyle(.secondary)
        if status?.source == "environment" {
          Text(
            store.text(
              "Ключ настроен на сервере. Его изменяют в конфигурации сервера.",
              "The key is configured on the server. Change it in the server configuration.")
          ).font(.caption).foregroundStyle(.secondary)
        } else {
          Button(store.text("Настроить модель и ключ", "Configure model and key")) {
            secretEditor = .ai
          }.frame(minHeight: 44).disabled(!store.canWrite)
          if status?.configured == true {
            Button(store.text("Отключить ИИ", "Disconnect AI"), role: .destructive) {
              confirmation = .ai
            }.frame(minHeight: 44).disabled(!store.canWrite)
          }
        }
        Text(
          store.text(
            "Запросы используют API-баланс провайдера, отдельно от подписки ChatGPT.",
            "Requests use your provider API balance, separate from a ChatGPT subscription.")
        ).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  private var telegramCard: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 14) {
        Label("Telegram", systemImage: "paperplane").font(.headline)
        Text(
          telegram == nil
            ? store.text("Статус пока не загружен", "Status is not loaded yet")
            : telegram?.linked == true
              ? store.text("Подключён · ", "Connected · ") + (telegram?.account?.firstName ?? "")
              : telegram?.configured == true
                ? store.text("Бот настроен, привяжите аккаунт", "Bot configured, link your account")
                : store.text("Бот не настроен", "Bot not configured")
        ).font(.subheadline).foregroundStyle(.secondary)
        Button(store.text("Настроить токен бота", "Configure bot token")) {
          secretEditor = .telegram
        }.frame(minHeight: 44).disabled(!store.canWrite)
        if telegram?.configured == true && telegram?.linked != true {
          Button(store.text("Получить ссылку привязки", "Get pairing link")) {
            Task {
              if let result = await store.write({ try await $0.pairTelegram() }) {
                telegram = result
              }
            }
          }.frame(minHeight: 44).disabled(!store.canWrite)
        }
        if let url = safePairingURL {
          Button {
            openURL(url)
          } label: {
            Label(
              store.text("Открыть Telegram и нажать Start", "Open Telegram and tap Start"),
              systemImage: "arrow.up.right.square"
            ).frame(minHeight: 44)
          }
        }
        if telegram?.linked == true {
          Toggle(store.text("Напоминания в Telegram", "Telegram reminders"), isOn: $reminderEnabled)
            .onChange(of: reminderEnabled) { _, _ in reminderDirty = true }
          Picker(store.text("За сколько минут", "Minutes before"), selection: $reminderLead) {
            ForEach([0, 5, 10, 15, 30, 60], id: \.self) {
              Text(
                $0 == 0
                  ? store.text("В момент начала", "At start") : "\($0) " + store.text("мин", "min")
              ).tag($0)
            }
          }.frame(minHeight: 44).onChange(of: reminderLead) { _, _ in reminderDirty = true }
          if let status = telegram?.reminders {
            Text(
              status.ready && status.schedulerActive
                ? store.text("Серверный планировщик готов", "Server scheduler is ready")
                : status.problem
                  ?? store.text(
                    "Планировщик пока не готов. Проверьте Google и серверную настройку.",
                    "Scheduler is not ready. Check Google and server configuration.")
            ).font(.caption).foregroundStyle(.secondary)
          }
          Button(store.text("Сохранить напоминания", "Save reminders")) {
            Task {
              if let result = await store.write({
                try await $0.saveTelegramReminders(
                  enabled: reminderEnabled, leadMinutes: reminderLead)
              }) {
                telegram = result
                reminderDirty = false
              }
            }
          }.frame(minHeight: 44).disabled(!store.canWrite || !reminderDirty)
          Button(store.text("Отправить тестовое уведомление", "Send test notification")) {
            Task {
              if await store.performMutation({ try await $0.testTelegramReminder() }) {
                notice = store.text(
                  "Сервер подтвердил отправку тестового уведомления.",
                  "The server confirmed sending the test notification.")
              }
            }
          }.frame(minHeight: 44).disabled(!store.canWrite)
        }
        if telegram?.configured == true {
          Button(store.text("Отключить Telegram", "Disconnect Telegram"), role: .destructive) {
            confirmation = .telegram
          }.frame(minHeight: 44).disabled(!store.canWrite)
        }
      }
    }
  }
  private var syncCard: some View {
    RitmCard {
      VStack(alignment: .leading, spacing: 14) {
        Label(
          store.text("Синхронизация и безопасность", "Sync and security"),
          systemImage: "lock.shield"
        ).font(.headline)
        Text(
          store.text(
            "Веб и iPhone используют один аккаунт и сервер. Без интернета отображаются последние данные текущей сессии; изменения временно недоступны. Секрет сессии хранится в Keychain.",
            "The web and iPhone share one account and server. Offline, the app shows the latest session data; editing is temporarily unavailable. Your session credential is stored in Keychain."
          )
        ).font(.caption).foregroundStyle(.secondary)
        Button {
          Task {
            await store.refresh()
            await loadIntegrations()
          }
        } label: {
          Label(store.text("Обновить данные", "Refresh data"), systemImage: "arrow.clockwise")
            .frame(minHeight: 44)
        }.disabled(store.isLoading || store.isMutating)
        LabeledContent(store.text("Версия", "Version"), value: appVersion).font(.caption)
        Link(destination: URL(string: "https://ritm-eta-hazel.vercel.app")!) {
          Label(
            store.text("Открыть сайт Ritm", "Open Ritm website"),
            systemImage: "arrow.up.right.square"
          ).frame(minHeight: 44)
        }
        Button(store.text("Выйти из аккаунта", "Sign out"), role: .destructive) {
          confirmingLogout = true
        }.frame(minHeight: 44).disabled(store.isMutating)
      }
    }
  }
  private var googleLabel: String {
    guard let google else {
      return store.text("Статус пока не загружен", "Status is not loaded yet")
    }
    switch google.status {
    case .connected: return store.text("Основной календарь подключён", "Primary calendar connected")
    case .reauthRequired: return store.text("Нужно подключить заново", "Reconnection required")
    case .disconnected: return store.text("Не подключён", "Not connected")
    case .unconfigured:
      return store.text("Нужна настройка OAuth клиента", "OAuth client setup required")
    }
  }
  private var safePairingURL: URL? {
    guard let raw = telegram?.pairingUrl, let url = URL(string: raw), url.scheme == "https",
      url.host == "t.me", url.user == nil, url.password == nil,
      let expires = telegram?.pairingExpiresAt, expires > Date().timeIntervalSince1970 * 1000
    else { return nil }
    return url
  }
  private var appVersion: String {
    "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))"
  }
  private func loadIntegrations() async {
    guard !loadingIntegrations, store.isSignedIn, navigation.section == .settings else { return }
    loadingIntegrations = true
    defer { loadingIntegrations = false }
    if let result = await store.read({ try await $0.googleStatus() }) { google = result }
    if let result = await store.read({ try await $0.googleConfiguration() }) {
      googleSetup = result
    }
    if let result = await store.read({ try await $0.telegramStatus() }) {
      telegram = result
      if !reminderDirty {
        reminderEnabled = result.reminders?.enabled ?? false
        reminderLead = result.reminders?.leadMinutes ?? 15
      }
    }
  }
  private func saveSettings() async {
    guard valid else { return }
    var value = draft
    value.displayName = value.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    value.email = value.email.trimmingCharacters(in: .whitespacesAndNewlines)
    let permissionDenied =
      value.notifications ? !(await store.requestNotificationPermission()) : false
    if let saved = await store.saveSettings(value) {
      baseline = saved
      draft = saved
      notice =
        permissionDenied
        ? store.text(
          "Настройки сохранены. Уведомления на этом iPhone пока не разрешены; включите их в настройках iOS.",
          "Settings saved. Notifications are not yet allowed on this iPhone; enable them in iOS Settings."
        ) : store.text("Настройки сохранены.", "Settings saved.")
      await store.updateLocalNotifications()
    }
  }
  private func disconnect(_ kind: IntegrationKind) async {
    confirmation = nil
    switch kind {
    case .google:
      if let result = await store.write({ try await $0.disconnectGoogle() }) { google = result }
    case .ai: _ = await store.write { try await $0.disconnectAI() }
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
enum IntegrationKind: String, Identifiable {
  case google, ai, telegram
  var id: String { rawValue }
}
struct TimeStringPicker: View {
  let title: String
  @Binding var value: String
  let zone: String
  var body: some View {
    DatePicker(
      title,
      selection: Binding(
        get: {
          let date = FeatureDate.date("2026-01-01", zone: zone)
          let minutes = TaskSchedule.timeMinutes(value) ?? 0
          return FeatureDate.calendar(zone).date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: date) ?? date
        }, set: { value = FeatureDate.time($0, zone: zone) }), displayedComponents: .hourAndMinute
    ).environment(\.timeZone, TimeZone(identifier: zone) ?? .current).frame(minHeight: 44)
  }
}
private struct IntegrationSecretEditor: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  let kind: IntegrationKind
  let googleSetup: GoogleOAuthSetup?
  @State private var secret = ""
  @State private var clientID = ""
  @State private var model = ""
  @State private var busy = false
  @State private var deleteSetup = false
  private var valid: Bool {
    if kind == .google {
      return !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (!secret.isEmpty || googleSetup?.hasClientSecret == true)
    }
    if kind == .ai {
      return !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          if kind == .google {
            TextField("Client ID", text: $clientID).textInputAutocapitalization(.never)
              .autocorrectionDisabled()
            SecureField(
              googleSetup?.hasClientSecret == true
                ? store.text("Новый Client Secret (необязательно)", "New Client Secret (optional)")
                : "Client Secret", text: $secret
            ).textInputAutocapitalization(.never).autocorrectionDisabled()
            if let callback = googleSetup?.redirectUri {
              LabeledContent("Redirect URI") {
                Text(callback).font(.caption).textSelection(.enabled)
              }
            }
          } else {
            SecureField(kind == .ai ? "OpenAI API key" : "Telegram Bot Token", text: $secret)
              .textInputAutocapitalization(.never).autocorrectionDisabled()
            if kind == .ai {
              TextField(store.text("Модель", "Model"), text: $model).textInputAutocapitalization(
                .never
              ).autocorrectionDisabled()
            }
          }
        } footer: {
          Text(
            store.text(
              "Секрет отправляется защищённым запросом на ваш сервер Ritm. В телефоне он не сохраняется; при сворачивании введённое значение очищается.",
              "The secret is sent securely to your Ritm server. It is not saved on your phone; the input is cleared when the app leaves the foreground."
            ))
        }
        if let error = store.errorMessage { Section { RitmErrorBanner(message: error) } }
        if store.uncertainWrite {
          Section {
            Button(store.text("Закрыть и проверить подключение", "Close and check connection")) {
              secret = ""
              dismiss()
            }
          }
        }
        if kind == .google && googleSetup?.source == "saved" {
          Section {
            Button(
              store.text("Удалить OAuth конфигурацию", "Delete OAuth configuration"),
              role: .destructive
            ) { deleteSetup = true }.disabled(!store.canWrite)
          }
        }
      }
      .navigationTitle(kind == .google ? "Google OAuth" : kind == .ai ? "OpenAI" : "Telegram")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(store.text("Отмена", "Cancel")) {
            secret = ""
            dismiss()
          }.disabled(busy)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(store.text("Сохранить", "Save")) { Task { await save() } }.disabled(
            !valid || busy || !store.canWrite)
        }
      }
      .onAppear {
        clientID = googleSetup?.clientId ?? ""
        model = store.bootstrap?.aiStatus.model ?? ""
      }
      .onChange(of: scenePhase) { _, phase in if phase != .active { secret = "" } }
      .onDisappear { secret = "" }
      .interactiveDismissDisabled(busy)
      .confirmationDialog(
        store.text("Удалить конфигурацию Google?", "Delete Google configuration?"),
        isPresented: $deleteSetup, titleVisibility: .visible
      ) {
        Button(store.text("Удалить", "Delete"), role: .destructive) {
          Task {
            if await store.write({ try await $0.removeGoogleConfiguration() }) != nil {
              secret = ""
              dismiss()
            }
          }
        }
      }
    }
  }
  private func save() async {
    busy = true
    defer { busy = false }
    let value = secret.trimmingCharacters(in: .whitespacesAndNewlines)
    var succeeded = false
    switch kind {
    case .google:
      succeeded =
        await store.write {
          try await $0.configureGoogle(
            GoogleOAuthSetupInput(
              clientId: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
              clientSecret: value.isEmpty ? nil : value))
        } != nil
    case .ai:
      succeeded =
        await store.write {
          try await $0.configureAI(
            apiKey: value, model: model.trimmingCharacters(in: .whitespacesAndNewlines))
        } != nil
    case .telegram:
      succeeded = await store.write { try await $0.configureTelegram(botToken: value) } != nil
    }
    if succeeded {
      secret = ""
      dismiss()
    }
  }
}
