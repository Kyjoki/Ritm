import SwiftUI

struct LoginView: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.scenePhase) private var scenePhase
  @State private var login = ""
  @State private var password = ""
  @State private var showingServer = false
  @FocusState private var focusedField: Field?
  private enum Field { case login, password }
  private var busy: Bool { store.isLoading || store.isMutating }

  var body: some View {
    ZStack {
      RitmBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          VStack(alignment: .leading, spacing: 14) {
            RitmMark()
              .frame(width: 44, height: 44)
              .foregroundStyle(RitmTheme.ink)
              .frame(width: 64, height: 64)
              .background(RitmTheme.lavender.gradient, in: RoundedRectangle(cornerRadius: 21))
              .accessibilityHidden(true)
            Text("Ritm").font(.largeTitle.bold())
            Text(store.text("Ваши дела. Ваш темп.", "Your plans. Your pace."))
              .font(.title3).foregroundStyle(.secondary)
          }
          RitmCard(reveal: 0) {
            VStack(alignment: .leading, spacing: 20) {
              Text(store.text("С возвращением", "Welcome back")).font(.title2.bold())
              Text(
                store.text(
                  "Войдите в тот же аккаунт, что и на сайте.",
                  "Sign in with the account you use on the website.")
              )
              .font(.subheadline).foregroundStyle(.secondary)
              VStack(alignment: .leading, spacing: 8) {
                Text(store.text("Логин", "Username")).font(.subheadline.weight(.medium))
                TextField(store.text("Логин владельца", "Owner username"), text: $login)
                  .textContentType(.username)
                  .keyboardType(.emailAddress)
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .disabled(busy)
                  .submitLabel(.next)
                  .focused($focusedField, equals: .login)
                  .onSubmit { focusedField = .password }
                  .padding(14)
                  .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
              }
              VStack(alignment: .leading, spacing: 8) {
                Text(store.text("Пароль", "Password")).font(.subheadline.weight(.medium))
                SecureField(store.text("Пароль", "Password"), text: $password)
                  .textContentType(.password)
                  .disabled(busy)
                  .submitLabel(.go)
                  .focused($focusedField, equals: .password)
                  .onSubmit { signIn() }
                  .padding(14)
                  .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
              }
              if let message = store.errorMessage { RitmErrorBanner(message: message) }
              Button(action: signIn) {
                HStack {
                  if busy { ProgressView().tint(RitmTheme.ink) }
                  Text(store.text("Войти", "Sign in"))
                  Image(systemName: "arrow.right")
                }
              }
              .buttonStyle(RitmPrimaryButtonStyle())
              .disabled(
                login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty
                  || busy)
            }
          }
          Label(
            store.text(
              "Общее пространство на ваших устройствах", "One workspace across your devices"),
            systemImage: "lock.shield"
          )
          .font(.footnote).foregroundStyle(.secondary)
          // Without this a server that is down or moved would lock the owner out of Settings.
          DisclosureGroup(
            store.text("Адрес сервера", "Server address"), isExpanded: $showingServer
          ) {
            ServerAddressCard().padding(.top, 10)
          }
          .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.top, 48)
        .padding(.bottom, 28)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
    }.onChange(of: scenePhase) { _, phase in if phase != .active { password = "" } }
      .onDisappear { password = "" }
  }

  private func signIn() {
    guard !busy, !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty
    else { return }
    focusedField = nil
    Task {
      await store.signIn(login: login, password: password)
      if store.isSignedIn { password = "" }
    }
  }
}
