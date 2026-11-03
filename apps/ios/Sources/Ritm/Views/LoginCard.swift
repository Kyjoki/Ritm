import SwiftUI

/// The sign-in form, shown inside Settings while the app is signed out. The app itself is never
/// gated behind it: every page opens, and the saved login signs in again by itself (SessionVault).
struct LoginCard: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.scenePhase) private var scenePhase
  @State private var login = ""
  @State private var password = ""
  @FocusState private var focusedField: Field?
  private enum Field { case login, password }
  private var busy: Bool { store.isLoading || store.isMutating }

  var body: some View {
    SettingsCard(symbol: "person.crop.circle", title: store.text("Вход в аккаунт", "Sign in")) {
      SettingsHint(
        text: store.text(
          "Войдите в тот же аккаунт, что и на сайте.",
          "Sign in with the account you use on the website."))
      SettingsField(label: store.text("Логин", "Username")) {
        TextField("", text: $login, prompt: Text(store.text("Логин владельца", "Owner username")).foregroundColor(RitmTheme.muted))
          .textContentType(.username)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .disabled(busy)
          .submitLabel(.next)
          .focused($focusedField, equals: .login)
          .onSubmit { focusedField = .password }
      }
      SettingsField(label: store.text("Пароль", "Password")) {
        SecureField("", text: $password)
          .textContentType(.password)
          .disabled(busy)
          .submitLabel(.go)
          .focused($focusedField, equals: .password)
          .onSubmit { signIn() }
      }
      Button(action: signIn) {
        HStack {
          if busy { ProgressView().tint(RitmTheme.ctaInk) }
          Text(store.text("Войти", "Sign in"))
          RitmSymbol("arrow.right")
        }
      }
      .buttonStyle(SettingsPrimaryButtonStyle())
      .disabled(
        login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || busy)
      .padding(.top, 16)
    }
    .onChange(of: scenePhase) { _, phase in if phase != .active { password = "" } }
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

/// A slim reminder at the top of the pages other than Settings while the app is signed out.
struct RitmSignInBanner: View {
  @Environment(RitmStore.self) private var store
  @Environment(RitmNavigation.self) private var navigation

  var body: some View {
    HStack(spacing: 10) {
      RitmSymbol("person.crop.circle.badge.exclamationmark")
        .font(.system(size: 17))
        .foregroundStyle(RitmTheme.accentColor)
        .accessibilityHidden(true)
      Text(store.text("Войдите в аккаунт в Настройках", "Sign in from Settings"))
        .ritmFont(12, weight: .medium)
        .foregroundStyle(RitmTheme.text)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        navigation.section = .settings
      } label: {
        Text(store.text("Настройки", "Settings"))
      }
      .buttonStyle(RitmTextButtonStyle(size: 12))
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: 44)
    .background(RitmTheme.soft, in: RoundedRectangle(cornerRadius: 14, style: .circular))
    .accessibilityElement(children: .contain)
  }
}
