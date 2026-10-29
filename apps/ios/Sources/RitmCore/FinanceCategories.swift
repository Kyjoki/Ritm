import Foundation

/// One selectable operation category. `label` is the Russian name that is stored on the server.
public struct FinanceCategory: Equatable, Sendable {
  public let label: String
  public let english: String
  /// SF Symbol name (available since iOS 17).
  public let symbol: String

  public init(label: String, english: String, symbol: String) {
    self.label = label
    self.english = english
    self.symbol = symbol
  }
}

public enum FinanceCategories {
  public static let otherLabel = "Другое"
  public static let otherSymbol = "ellipsis.circle"

  private static let other = FinanceCategory(
    label: otherLabel, english: "Other", symbol: otherSymbol)

  public static let expense: [FinanceCategory] = [
    FinanceCategory(label: "Продукты", english: "Groceries", symbol: "cart"),
    FinanceCategory(label: "Кафе", english: "Dining", symbol: "cup.and.saucer"),
    FinanceCategory(label: "Транспорт", english: "Transport", symbol: "bus"),
    FinanceCategory(label: "Дом", english: "Home", symbol: "house"),
    FinanceCategory(label: "Здоровье", english: "Health", symbol: "cross.case"),
    FinanceCategory(label: "Покупки", english: "Shopping", symbol: "bag"),
    FinanceCategory(label: "Развлечения", english: "Entertainment", symbol: "ticket"),
    FinanceCategory(label: "Подарки", english: "Gifts", symbol: "gift"),
    FinanceCategory(label: "Спорт", english: "Sport", symbol: "dumbbell"),
    FinanceCategory(label: "Путешествия", english: "Travel", symbol: "suitcase"),
    FinanceCategory(label: "Образование", english: "Education", symbol: "graduationcap"),
    FinanceCategory(label: "Связь", english: "Telecom", symbol: "iphone"),
    FinanceCategory(label: "Одежда", english: "Clothes", symbol: "tshirt"),
    FinanceCategory(label: "Красота", english: "Beauty", symbol: "sparkles"),
    FinanceCategory(label: "Дети", english: "Kids", symbol: "face.smiling"),
    FinanceCategory(label: "Питомцы", english: "Pets", symbol: "pawprint"),
    FinanceCategory(label: "Платежи", english: "Bills", symbol: "creditcard"),
    other,
  ]

  public static let income: [FinanceCategory] = [
    FinanceCategory(label: "Зарплата", english: "Salary", symbol: "banknote"),
    FinanceCategory(label: "Подработка", english: "Side work", symbol: "briefcase"),
    // Shares the «Подарки» symbol, as in the prototype.
    FinanceCategory(label: "Подарок", english: "Gift", symbol: "gift"),
    FinanceCategory(label: "Проценты", english: "Interest", symbol: "percent"),
    FinanceCategory(label: "Возврат", english: "Refund", symbol: "arrow.uturn.backward"),
    FinanceCategory(label: "Продажа", english: "Sale", symbol: "tag"),
    other,
  ]

  /// The category for a stored label (trimmed, case-insensitive), nil when it is not in a list.
  public static func category(for label: String?) -> FinanceCategory? {
    let key = (label ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !key.isEmpty else { return nil }
    return (expense + income).first { $0.label.lowercased() == key }
  }

  public static func isKnown(_ label: String?) -> Bool { category(for: label) != nil }

  /// The SF Symbol for a stored category; unknown or empty gives the «Другое» symbol.
  public static func symbol(for category: String?) -> String {
    Self.category(for: category)?.symbol ?? otherSymbol
  }

  /// The English display name; unknown labels are shown as stored.
  public static func englishName(for category: String) -> String {
    Self.category(for: category)?.english ?? category
  }
}
