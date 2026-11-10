import RitmCore
import SwiftUI
import UniformTypeIdentifiers

/// A small muted paragraph used across the «Apple Wallet» settings card.
struct WalletNote: View {
  let text: String

  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .ritmFont(11, lineSpacing: 3.5)
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

/// The folder part of the Wallet page: what Ritm sees
/// right now, the import button, the picker and a way to forget the folder.
struct WalletFolderPanel: View {
  @Environment(RitmStore.self) private var store
  @State private var choosing = false
  @State private var confirmingForget = false

  var body: some View {
    let source = store.walletFolder
    let state = describe(source)
    VStack(alignment: .leading, spacing: 0) {
      SettingsGroup {
        SettingsInfoRow(
          icon: "folder", title: store.text("Папка «Ritm»", "Folder “Ritm”"), value: folderValue(source))
        SettingsInfoRow(
          title: store.text("Последний импорт", "Last import"),
          value: SettingsTrailing(source.lastImport.map { formatted($0.date) } ?? "—"))
      }
      SettingsFootnote(text: state.text, tone: state.isProblem ? .error : .none)
      if let extra = lastImportLine(source) { SettingsFootnote(text: extra) }
      SettingsButtonStack {
        SettingsActionButton(title: store.text("Импортировать сейчас", "Import now")) {
          Task { await store.importWalletFile(userInitiated: true) }
        }
        .disabled(!source.isChosen || source.isReading)
        SettingsActionButton(title: pickTitle(source), kind: .secondary) { choosing = true }
        if source.isChosen {
          SettingsActionButton(title: store.text("Забыть папку", "Forget folder"), kind: .dangerText) {
            confirmingForget = true
          }
        }
      }
      SettingsFootnote(
        text: store.text(
          "Заберёт новые строки из purchases.txt в «Новые покупки». Ritm делает это сам при открытии.",
          "Takes the new lines from purchases.txt into New purchases. Ritm also does this when it opens."))
    }
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

  /// The short state of the folder for its row.
  private func folderValue(_ source: WalletFolderSource) -> SettingsTrailing {
    switch source.status {
    case .ready: SettingsTrailing(store.text("Найдена", "Found"), .ok)
    case .notChosen: SettingsTrailing(store.text("Не выбрана", "Not chosen"), .none)
    case .downloading: SettingsTrailing(store.text("Загрузка", "Downloading"), .none)
    case .fileMissing: SettingsTrailing(store.text("Нет файла", "No file"), .warn)
    case .needsRepick: SettingsTrailing(store.text("Нужен доступ", "Access needed"), .warn)
    case .failed: SettingsTrailing(store.text("Ошибка", "Error"), .error)
    }
  }

  private func pickTitle(_ source: WalletFolderSource) -> String {
    switch source.status {
    case .notChosen: store.text("Выбрать папку Ritm", "Choose the Ritm folder")
    case .needsRepick: store.text("Выбрать папку заново", "Choose the folder again")
    default: store.text("Другая папка", "Another folder")
    }
  }

  // MARK: Status

  private struct Described {
    let text: String
    var isProblem = false
  }

  private func describe(_ source: WalletFolderSource) -> Described {
    let name = source.folderName ?? "Ritm"
    let fileName = WalletFileImport.fileName
    switch source.status {
    case .notChosen:
      return Described(
        text: store.text(
          "Папка не выбрана. Ritm прочитает файл \(fileName), когда вы его откроете.",
          "No folder chosen. Ritm reads \(fileName) when you open it."))
    case .ready:
      return Described(
        text: store.text("Папка «\(name)» · \(fileName)", "Folder “\(name)” · \(fileName)"))
    case .fileMissing:
      return Described(
        text: store.text(
          "В папке «\(name)» нет файла \(fileName). Его создаст действие «Добавить в файл» после первой оплаты.",
          "No \(fileName) in “\(name)”. The Append to File action creates it after the first payment."),
        isProblem: true)
    case .downloading:
      return Described(
        text: store.text(
          "Файл ещё загружается из iCloud. Подождите немного и нажмите «Импортировать сейчас».",
          "The file is still downloading from iCloud. Wait a moment, then tap Import now."))
    case .needsRepick:
      return Described(
        text: store.text(
          "Нет доступа к папке: доступ устарел или папку удалили. Выберите папку Ritm заново.",
          "No access to the folder: the access expired or it was removed. Choose the Ritm folder again."),
        isProblem: true)
    case .failed(let reason):
      let extra = reason.isEmpty ? "" : " (\(reason))"
      return Described(
        text: store.text(
          "Не удалось прочитать файл. Попробуйте ещё раз или выберите папку заново\(extra).",
          "Could not read the file. Try again or choose the folder again\(extra)."),
        isProblem: true)
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
    let formatter = Self.formatter(ru: store.language == .ru, zone: store.timeZone)
    return formatter.string(from: date)
  }

  /// One formatter per (language, zone) pair: building one is slow, and this runs per render.
  @MainActor private static var formatters: [String: DateFormatter] = [:]

  @MainActor private static func formatter(ru: Bool, zone: String) -> DateFormatter {
    let key = "\(ru)|\(zone)"
    if let cached = formatters[key] { return cached }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: ru ? "ru_RU" : "en_US")
    formatter.timeZone = TimeZone(identifier: zone)
    formatter.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
    formatters[key] = formatter
    return formatter
  }
}
