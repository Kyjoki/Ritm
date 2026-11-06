import Foundation

/// The extension reads an App Group projection, never the app's private Keychain or live database.
public enum WidgetSnapshotStore {
  public static let kind = "RitmDayHabits"
  public static let maximumBytes = 96 * 1024
  private static let filename = "day-widget-v1.json"

  public static var container: URL? {
    #if os(iOS)
    let configured = Bundle.main.object(forInfoDictionaryKey: "RitmAppGroup") as? String
    let root = Bundle.main.bundleIdentifier?.replacingOccurrences(of: ".RitmWidgets", with: "")
    let candidates = [root.map { "group." + $0 }, configured].compactMap { $0 }
    return candidates.lazy.compactMap {
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
    }.first
    #else
    return nil
    #endif
  }

  public static func read() -> DayWidgetSnapshot? {
    guard let container else { return nil }
    return read(in: container)
  }
  public static func read(in directory: URL) -> DayWidgetSnapshot? {
    let file = directory.appendingPathComponent(filename)
    guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      size <= maximumBytes, let data = try? Data(contentsOf: file), data.count <= maximumBytes,
      let value = try? JSONDecoder().decode(DayWidgetSnapshot.self, from: data),
      value.schemaVersion == DayWidgetSnapshot.schema else { return nil }
    return value
  }
  @discardableResult public static func write(_ value: DayWidgetSnapshot) -> Bool {
    guard let container else { return false }
    return write(value, in: container)
  }
  @discardableResult public static func write(_ value: DayWidgetSnapshot, in directory: URL) -> Bool {
    do {
      let data = try JSONEncoder().encode(value)
      guard data.count <= maximumBytes else { return false }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      #if os(iOS)
      try data.write(to: directory.appendingPathComponent(filename),
        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      #else
      try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
      #endif
      return true
    } catch { return false }
  }
  public static func clear() {
    guard let container else { return }
    try? FileManager.default.removeItem(at: container.appendingPathComponent(filename))
  }
}
