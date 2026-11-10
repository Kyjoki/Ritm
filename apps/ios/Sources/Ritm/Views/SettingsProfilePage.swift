import RitmCore
import SwiftUI

/// A `.row` with a label on the left and an input on the right (`.inl`): the whole row focuses it.
private struct SettingsInputRow: View {
  let title: String
  let prompt: String
  @Binding var text: String
  var focus: FocusState<Bool>.Binding
  var keyboard: UIKeyboardType = .default
  var contentType: UITextContentType?
  var capitalization: TextInputAutocapitalization = .sentences

  var body: some View {
    HStack(spacing: 12) {
      Text(title)
        .ritmFont(15, weight: .medium, tracking: -0.012)
        .foregroundStyle(RitmTheme.text)
      TextField(title, text: $text, prompt: Text(prompt).foregroundColor(RitmTheme.muted))
        .ritmFont(15)
        .foregroundStyle(RitmTheme.text)
        .multilineTextAlignment(.trailing)
        .keyboardType(keyboard)
        .textContentType(contentType)
        .textInputAutocapitalization(capitalization)
        .autocorrectionDisabled()
        .focused(focus)
        .submitLabel(.done)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
    }
    .padding(.horizontal, 16)
    .frame(minHeight: 46)
    .contentShape(Rectangle())
    .onTapGesture { focus.wrappedValue = true }
  }
}

/// «Профиль»: the avatar, the name and the email (saved as you type, after a short pause) and
/// the sign-out button with its confirmation.
struct SettingsProfilePage: View {
  @Environment(RitmStore.self) private var store
  @Environment(SettingsModel.self) private var model
  @FocusState private var nameFocused: Bool
  @FocusState private var emailFocused: Bool
  @State private var confirmingSignOut = false

  private var draft: AccountSettings { model.draft }

  var body: some View {
    SettingsPage(title: model.text("Профиль", "Profile")) {
      header
      SettingsGroup {
        SettingsInputRow(
          title: model.text("Имя", "Name"), prompt: model.text("Твоё имя", "Your name"),
          text: Binding(
            get: { draft.displayName },
            set: { model.edit(AccountSettingsPatch(displayName: String($0.prefix(SettingsValidator.nameLimit)))) }),
          focus: $nameFocused, contentType: .name)
        SettingsInputRow(
          title: model.text("Почта", "Email"), prompt: model.text("Твоя почта", "Your email"),
          text: Binding(
            get: { draft.email }, set: { model.edit(AccountSettingsPatch(email: $0)) }),
          focus: $emailFocused, keyboard: .emailAddress, contentType: .emailAddress,
          capitalization: .never)
      }
      if let issue = model.heldIssue {
        SettingsFootnote(text: issue.message(model.language), tone: .error)
      } else {
        SettingsFootnote(
          text: model.text(
            "Для профиля. Почтовые уведомления пока не подключены.",
            "For your profile. Email notifications are not connected yet."))
      }
      SettingsButtonStack {
        SettingsActionButton(
          title: model.text("Выйти из аккаунта", "Sign out"), icon: "rectangle.portrait.and.arrow.right",
          kind: .danger
        ) { confirmingSignOut = true }
        .disabled(store.isMutating)
      }
      .padding(.top, 10)
    }
    .onChange(of: nameFocused) { _, focused in if !focused { Task { await model.settle() } } }
    .onChange(of: emailFocused) { _, focused in if !focused { Task { await model.settle() } } }
    .confirmationDialog(
      model.text("Выйти из аккаунта?", "Sign out?"), isPresented: $confirmingSignOut,
      titleVisibility: .visible
    ) {
      Button(model.text("Выйти", "Sign out"), role: .destructive) { Task { await store.signOut() } }
    } message: {
      Text(model.text("Чтобы войти снова, потребуется ввести данные аккаунта.", "You will need your account details to sign in again."))
    }
  }

  /// The big avatar, the name and the email above the fields.
  private var header: some View {
    VStack(spacing: 10) {
      SettingsAvatar(name: draft.displayName, size: 72)
      VStack(spacing: 2) {
        Text(draft.displayName.isEmpty ? model.text("Твоё имя", "Your name") : draft.displayName)
          .ritmFont(19, weight: .bold, tracking: -0.03)
          .foregroundStyle(RitmTheme.text)
        if !draft.email.isEmpty {
          Text(draft.email).ritmFont(13).foregroundStyle(RitmTheme.muted)
        }
      }
      .multilineTextAlignment(.center)
      .accessibilityElement(children: .combine)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 6)
    .padding(.bottom, 18)
  }
}
