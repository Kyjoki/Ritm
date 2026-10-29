import RitmCore
import SwiftUI

/// «Адрес сервера»: where this iPhone finds Ritm (for example the owner's laptop over Tailscale).
/// The address is checked with the public /api/health before it is saved.
struct ServerAddressCard: View {
  @Environment(RitmStore.self) private var store
  @State private var text = ""
  @State private var checking = false
  @State private var message: String?
  @State private var failed = false
  @State private var confirmingReset = false
  @FocusState private var focused: Bool

  private var busy: Bool { checking || store.isMutating || store.isLoading }

  var body: some View {
    SettingsCard(symbol: "network", title: store.text("Адрес сервера", "Server address")) {
      SettingsField(label: store.text("Адрес", "Address")) {
        TextField("", text: $text, prompt: Text("https://…").foregroundColor(RitmTheme.muted))
          .keyboardType(.URL)
          .textContentType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .submitLabel(.done)
          .focused($focused)
          .disabled(busy)
          .onSubmit { Task { await checkAndSave() } }
          .onChange(of: focused) { _, isFocused in
            if isFocused { message = nil }
          }
      }
      if let message {
        Label(message, systemImage: failed ? "exclamationmark.circle" : "checkmark.circle")
          .ritmFont(11, lineSpacing: 3)
          .foregroundStyle(failed ? RitmTheme.danger : RitmTheme.accentColor)
          .padding(.top, 10)
      } else {
        SettingsHint(
          text: store.text(
            "Сейчас: \(store.serverAddress.origin). Только https, например адрес ноутбука в Tailscale.",
            "Now: \(store.serverAddress.origin). https only, for example your laptop's Tailscale address."
          ))
      }
      SettingsHint(
        text: store.text(
          "После сохранения вы выйдете из аккаунта на этом iPhone: вход хранится отдельно для каждого сервера.",
          "Saving signs you out on this iPhone: the sign-in is kept separately for each server."))
      HStack(spacing: 10) {
        Button {
          Task { await checkAndSave() }
        } label: {
          HStack {
            if checking { ProgressView().tint(RitmTheme.ink) }
            Text(
              checking
                ? store.text("Проверяем…", "Checking…")
                : store.text("Проверить и сохранить", "Check and save"))
          }
        }
        .buttonStyle(RitmPrimaryButtonStyle(minHeight: 48))
        .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button(store.text("Сбросить", "Reset")) { confirmingReset = true }
          .buttonStyle(RitmTextButtonStyle(size: 12))
          .disabled(busy || store.serverAddress == .production)
      }
      .padding(.top, 16)
    }
    .onAppear { text = store.serverAddress.origin }
    .confirmationDialog(
      store.text("Вернуть адрес по умолчанию?", "Restore the default address?"),
      isPresented: $confirmingReset, titleVisibility: .visible
    ) {
      Button(store.text("Сбросить и выйти", "Reset and sign out"), role: .destructive) {
        Task { await reset() }
      }
    } message: {
      Text(
        store.text(
          "Вы выйдете из аккаунта на этом iPhone. Адрес по умолчанию: \(ServerAddress.production.origin).",
          "You will be signed out on this iPhone. The default address is \(ServerAddress.production.origin)."
        ))
    }
  }

  private func checkAndSave() async {
    guard !busy else { return }
    focused = false
    let address: ServerAddress
    switch ServerAddress.validate(text) {
    case .failure(let error):
      show(error.localizedDescription, failed: true)
      return
    case .success(let value):
      address = value
    }
    guard address != store.serverAddress else {
      text = address.origin
      show(store.text("Этот адрес уже используется.", "This address is already in use."), failed: false)
      return
    }
    checking = true
    defer { checking = false }
    do {
      try await address.checkHealth()
    } catch is CancellationError {
      return
    } catch {
      show(error.localizedDescription, failed: true)
      return
    }
    await apply(address)
  }

  private func reset() async {
    guard !busy else { return }
    await apply(.production)
  }

  private func apply(_ address: ServerAddress) async {
    if await store.changeServer(to: address) {
      text = address.origin
      show(store.text("Адрес сохранён. Войдите на новом сервере.", "Address saved. Sign in on the new server."), failed: false)
    } else {
      show(
        store.text(
          "Не удалось сменить адрес. Дождитесь окончания загрузки и повторите.",
          "Could not change the address. Wait for loading to finish and try again."), failed: true)
    }
  }

  private func show(_ value: String, failed: Bool) {
    self.failed = failed
    message = value
  }
}
