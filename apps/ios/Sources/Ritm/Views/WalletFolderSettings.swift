import RitmCore
import SwiftUI
import UniformTypeIdentifiers

/// A small muted paragraph used across the «Apple Wallet» settings card.
struct WalletNote: View {
  let text: String

  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .ritmFont(11, lineSpacing: 3)
      .foregroundStyle(RitmTheme.muted)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// The system folder picker. No entitlements: the chosen folder arrives as a security-scoped URL
/// that `WalletFolderSource` turns into a bookmark.
struct WalletFolderPicker: UIViewControllerRepresentable {
  let onPick: (URL) -> Void
  let onCancel: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

  func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    picker.allowsMultipleSelection = false
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

  final class Coordinator: NSObject, UIDocumentPickerDelegate {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
      self.onPick = onPick
      self.onCancel = onCancel
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
      if let url = urls.first { onPick(url) } else { onCancel() }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onCancel() }
  }
}

/// The folder part of the «Apple Wallet» card: what Ritm sees right now, and the buttons to pick
/// the folder and import by hand.
struct WalletFolderPanel: View {
  @Environment(RitmStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var choosing = false
  @State private var confirmingForget = false

  var body: some View {
    let source = store.walletFolder
    VStack(alignment: .leading, spacing: 10) {
      statusBlock(source)
      HStack(spacing: 8) {
        SettingsSmallButton(title: pickTitle(source)) { choosing = true }
        SettingsSmallButton(title: store.text("Импортировать сейчас", "Import now")) {
          Task { await store.importWalletFile(userInitiated: true) }
        }
        .disabled(!source.isChosen || source.isReading)
        .opacity(!source.isChosen || source.isReading ? 0.5 : 1)
      }
      if source.isChosen {
        SettingsSmallButton(title: store.text("Забыть папку", "Forget folder")) {
          confirmingForget = true
        }
      }
    }
    .animation(reduceMotion ? nil : RitmMotion.easeOut(0.2), value: source.status)
    .sheet(isPresented: $choosing) {
      WalletFolderPicker(
        onPick: { url in
          store.walletFolder.choose(url)
          choosing = false
          Task { await store.importWalletFile(userInitiated: true) }
        },
        onCancel: { choosing = false }
      )
      .ignoresSafeArea()
    }
    .confirmationDialog(
      store.text("Забыть папку?", "Forget the folder?"), isPresented: $confirmingForget,
      titleVisibility: .visible
    ) {
      Button(store.text("Забыть", "Forget"), role: .destructive) { store.walletFolder.disconnect() }
      Button(store.text("Отмена", "Cancel"), role: .cancel) {}
    } message: {
      Text(
        store.text(
          "Ritm перестанет читать purchases.txt. Сам файл и папка останутся на месте.",
          "Ritm will stop reading purchases.txt. The file and the folder stay where they are."))
    }
  }

  private func pickTitle(_ source: WalletFolderSource) -> String {
    switch source.status {
    case .notChosen: store.text("Выбрать папку Ritm", "Choose the Ritm folder")
    case .needsRepick: store.text("Выбрать папку заново", "Choose the folder again")
    default: store.text("Сменить папку", "Change folder")
    }
  }

  // MARK: Status

  private func statusBlock(_ source: WalletFolderSource) -> some View {
    let state = describe(source)
    return VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: state.symbol)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(state.isProblem ? RitmTheme.danger : RitmTheme.accentColor)
          .accessibilityHidden(true)
        Text(state.title)
          .ritmFont(13, weight: .semibold)
          .foregroundStyle(state.isProblem ? RitmTheme.danger : RitmTheme.text)
          .fixedSize(horizontal: false, vertical: true)
      }
      WalletNote(state.detail)
      if let last = lastImportLine(source) { WalletNote(last) }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      state.isProblem ? RitmTheme.dangerSoft : RitmTheme.glassDense,
      in: RoundedRectangle(cornerRadius: 11, style: .circular)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 11, style: .circular)
        .strokeBorder(state.isProblem ? RitmTheme.danger.opacity(0.4) : RitmTheme.line, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(store.text("Состояние папки", "Folder status"))
    .accessibilityValue(
      [state.title, state.detail, lastImportLine(source)].compactMap { $0 }.joined(separator: ". "))
  }

  private struct Described {
    let symbol: String
    let title: String
    let detail: String
    var isProblem = false
  }

  private func describe(_ source: WalletFolderSource) -> Described {
    let name = source.folderName ?? "Ritm"
    let fileName = WalletFileImport.fileName
    switch source.status {
    case .notChosen:
      return Described(
        symbol: "folder.badge.questionmark",
        title: store.text("Папка не выбрана", "No folder chosen"),
        detail: store.text(
          "Создайте папку Ritm в приложении «Файлы» (iCloud Drive или «На iPhone») и выберите её здесь.",
          "Create a Ritm folder in the Files app (iCloud Drive or On My iPhone) and choose it here."
        ))
    case .ready:
      return Described(
        symbol: "checkmark.circle",
        title: store.text("Папка выбрана: «\(name)»", "Folder chosen: “\(name)”"),
        detail: store.text(
          "Ritm читает файл \(fileName), когда вы его открываете, и никогда не меняет и не удаляет. Очистить файл можно самому в «Файлах».",
          "Ritm reads \(fileName) when you open it and never changes or deletes it. You can clear the file yourself in Files."
        ))
    case .fileMissing:
      return Described(
        symbol: "doc.questionmark",
        title: store.text("В папке «\(name)» нет файла \(fileName)", "No \(fileName) in “\(name)”"),
        detail: store.text(
          "Файл создаст действие «Добавить в файл» после первой оплаты. Имя должно быть точно \(fileName), папка та же. Проверьте действие в «Командах».",
          "The Append to File action creates it after the first payment. The name must be exactly \(fileName) in this same folder. Check the action in Shortcuts."
        ), isProblem: true)
    case .downloading:
      return Described(
        symbol: "icloud.and.arrow.down",
        title: store.text("Файл ещё загружается из iCloud", "The file is still downloading from iCloud"),
        detail: store.text(
          "Ritm запросил его. Подождите немного и нажмите «Импортировать сейчас».",
          "Ritm asked for it. Wait a moment, then tap Import now."))
    case .needsRepick:
      return Described(
        symbol: "exclamationmark.triangle",
        title: store.text("Нет доступа к папке", "No access to the folder"),
        detail: store.text(
          "Доступ устарел или папку удалили. Выберите папку Ritm заново.",
          "The access expired or the folder was removed. Choose the Ritm folder again."),
        isProblem: true)
    case .failed(let reason):
      let extra = reason.isEmpty ? "" : " (\(reason))"
      return Described(
        symbol: "exclamationmark.triangle",
        title: store.text("Не удалось прочитать файл", "Could not read the file"),
        detail: store.text(
          "Попробуйте ещё раз или выберите папку заново\(extra).",
          "Try again or choose the folder again\(extra)."), isProblem: true)
    }
  }

  private func lastImportLine(_ source: WalletFolderSource) -> String? {
    guard source.isChosen, let last = source.lastImport else { return nil }
    let when = formatted(last.date)
    var parts = [
      store.text("новых: \(last.added)", "new: \(last.added)"),
      store.text("уже были: \(last.duplicates)", "already seen: \(last.duplicates)"),
    ]
    if last.skipped > 0 {
      parts.append(store.text("пропущено строк: \(last.skipped)", "lines skipped: \(last.skipped)"))
    }
    if last.overflow > 0 {
      parts.append(
        store.text("не поместилось: \(last.overflow)", "did not fit: \(last.overflow)"))
    }
    return store.text("Последний импорт \(when): ", "Last import \(when): ")
      + parts.joined(separator: ", ")
  }

  private func formatted(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: store.language == .ru ? "ru_RU" : "en_US")
    formatter.timeZone = TimeZone(identifier: store.timeZone)
    formatter.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
    return formatter.string(from: date)
  }
}
