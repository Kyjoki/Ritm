import RitmCore
import SwiftUI

/// The sign-in form, shown inside Settings while the app is signed out. The app itself is never
/// gated behind it: every page opens. The password is never stored; the device session lasts
/// until it expires or is revoked, then this form comes back.
struct LoginCard: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.scenePhase) private var scenePhase
  @State private var login = ""
  @State private var password = ""
  /// Six-digit authenticator code or a recovery code; held only while typing, never persisted.
  @State private var code = ""
  @State private var useRecoveryCode = false
  @FocusState private var focusedField: Field?
  private enum Field { case login, password, code }
  private static let codeLength = 6
  private static let recoveryCodeMaxLength = 64
  private var busy: Bool { store.isLoading || store.isMutating }
  private var secondStep: Bool { store.secondFactorRequired }
  private var trimmedLogin: String { login.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var trimmedCode: String { code.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var codeReady: Bool {
    !secondStep || (useRecoveryCode ? !trimmedCode.isEmpty : trimmedCode.count == Self.codeLength)
  }
  private var canSubmit: Bool { !trimmedLogin.isEmpty && !password.isEmpty && codeReady && !busy }

  var body: some View {
    SettingsCard(symbol: "person.crop.circle", title: store.text("Вход в аккаунт", "Sign in")) {
      SettingsHint(
        text: store.text(
          "Войдите в тот же аккаунт, что и на сайте.",
          "Sign in with the account you use on the website."))
      if store.serverAddress != .production {
        Label {
          Text(
            store.text(
              "Вход и данные будут отправлены на сервер \(store.serverAddress.origin).",
              "Your sign-in and data will be sent to \(store.serverAddress.origin)."))
        } icon: {
          RitmSymbol("exclamationmark.triangle")
        }
        .ritmFont(11, lineSpacing: 3.5)
        .foregroundStyle(RitmTheme.danger)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
      }
      SettingsField(label: store.text("Логин", "Username")) {
        TextField("", text: $login, prompt: Text(store.text("Логин владельца", "Owner username")).foregroundColor(RitmTheme.muted))
          .textContentType(.username)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .disabled(busy || secondStep)
          .submitLabel(.next)
          .focused($focusedField, equals: .login)
          .onSubmit { focusedField = .password }
      }
      SettingsField(label: store.text("Пароль", "Password")) {
        SecureField("", text: $password)
          .textContentType(.password)
          .disabled(busy || secondStep)
          .submitLabel(.go)
          .focused($focusedField, equals: .password)
          .onSubmit { signIn() }
      }
      if secondStep { secondFactorFields }
      if let failure = store.loginFailure {
        Label { Text(failure) } icon: { RitmSymbol("exclamationmark.circle") }
          .ritmFont(11, lineSpacing: 3.5)
          .foregroundStyle(RitmTheme.danger)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 10)
          .accessibilityAddTraits(.updatesFrequently)
      }
      Button(action: signIn) {
        HStack {
          if busy { ProgressView().tint(RitmTheme.ctaInk) }
          Text(store.text("Войти", "Sign in"))
          RitmSymbol("arrow.right")
        }
      }
      .buttonStyle(SettingsPrimaryButtonStyle())
      .disabled(!canSubmit)
      .padding(.top, 16)
      if secondStep {
        Button(store.text("Назад", "Back"), action: goBack)
          .buttonStyle(SettingsTextButtonStyle(size: 11))
          .disabled(busy)
      }
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase != .active else { return }
      code = ""
      // Between the two steps the password stays so the owner can read the code in the
      // authenticator app; it is dropped on Back, on success and when the page goes away.
      if !secondStep { password = "" }
    }
    .onChange(of: store.secondFactorRequired) { _, required in
      code = ""
      if required { focusedField = .code }
    }
    .onDisappear {
      password = ""
      code = ""
      store.cancelSecondFactor()
    }
  }

  @ViewBuilder private var secondFactorFields: some View {
    SettingsField(
      label: useRecoveryCode
        ? store.text("Код восстановления", "Recovery code")
        : store.text("Код из приложения", "Authenticator code")
    ) {
      TextField("", text: $code, prompt: Text(useRecoveryCode ? "" : "000000").foregroundColor(RitmTheme.muted))
        .textContentType(useRecoveryCode ? nil : .oneTimeCode)
        .keyboardType(useRecoveryCode ? .asciiCapable : .numberPad)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .disabled(busy)
        .submitLabel(.go)
        .focused($focusedField, equals: .code)
        .onChange(of: code) { _, value in
          let limited =
            useRecoveryCode
            ? String(value.prefix(Self.recoveryCodeMaxLength))
            : String(value.filter { $0.isASCII && $0.isNumber }.prefix(Self.codeLength))
          if limited != value { code = limited }
        }
        .onSubmit { signIn() }
    }
    Button(
      useRecoveryCode
        ? store.text("Использовать код из приложения", "Use the authenticator code")
        : store.text("Использовать код восстановления", "Use a recovery code")
    ) {
      useRecoveryCode.toggle()
      code = ""
      focusedField = .code
    }
    .buttonStyle(SettingsTextButtonStyle(size: 11))
    .disabled(busy)
  }

  private func goBack() {
    password = ""
    code = ""
    useRecoveryCode = false
    store.cancelSecondFactor()
  }

  private func signIn() {
    guard canSubmit else { return }
    focusedField = nil
    let submitted = trimmedCode
    let asRecovery = secondStep && useRecoveryCode
    let asTotp = secondStep && !useRecoveryCode
    Task {
      await store.signIn(
        login: login, password: password,
        totp: asTotp ? submitted : nil, recoveryCode: asRecovery ? submitted : nil)
      // A code is single-use: never keep it, whatever the outcome.
      code = ""
      if store.isSignedIn {
        password = ""
        useRecoveryCode = false
      }
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
