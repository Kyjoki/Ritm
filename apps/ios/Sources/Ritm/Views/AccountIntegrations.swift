import RitmCore
import SwiftUI

enum IntegrationKind: String, Identifiable {
  case google, ai, telegram
  var id: String { rawValue }
}
/// `<input type=time>` of the settings card: the value and a clock; a tap opens a wheel in a popover.
struct TimeStringPicker: View {
  let title: String
  @Binding var value: String
  let zone: String
  @State private var open = false

  private var date: Binding<Date> {
    Binding(
      get: {
        let day = FeatureDate.date("2026-01-01", zone: zone)
        let minutes = TaskSchedule.timeMinutes(value) ?? 0
        return FeatureDate.calendar(zone).date(
          bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
      }, set: { value = FeatureDate.time($0, zone: zone) })
  }

  var body: some View {
    Button {
      open = true
    } label: {
      HStack {
        Text(value).monospacedDigit()
        Spacer(minLength: 8)
        RitmSymbol("clock").font(.system(size: 15)).foregroundStyle(RitmTheme.muted)
      }
      .frame(maxWidth: .infinity, minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityValue(value)
    .popover(isPresented: $open) {
      DatePicker("", selection: date, displayedComponents: .hourAndMinute)
        .datePickerStyle(.wheel)
        .labelsHidden()
        .environment(\.timeZone, TimeZone(identifier: zone) ?? .current)
        .frame(width: 200, height: 160)
        .padding(12)
        .presentationCompactAdaptation(.popover)
    }
  }
}
struct IntegrationSecretEditor: View {
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
  /// The saved secret belongs to one OAuth client: it is kept only while the Client ID is
  /// unchanged (GoogleSetupDialog `keepingSecret`).
  private var keepingGoogleSecret: Bool {
    googleSetup?.hasClientSecret == true
      && clientID.trimmingCharacters(in: .whitespacesAndNewlines) == googleSetup?.clientId
  }
  private var valid: Bool {
    if kind == .google {
      let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
      let newSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
      return id.range(
        of: #"^[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$"#, options: .regularExpression)
        != nil
        && (newSecret.isEmpty ? keepingGoogleSecret : !newSecret.contains(where: \.isWhitespace))
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
