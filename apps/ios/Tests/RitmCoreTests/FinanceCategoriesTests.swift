import XCTest

@testable import RitmCore

final class FinanceCategoriesTests: XCTestCase {
  func testListsMatchTheApprovedDesign() {
    XCTAssertEqual(
      FinanceCategories.expense.map(\.label),
      [
        "Продукты", "Кафе", "Транспорт", "Дом", "Здоровье", "Покупки", "Развлечения", "Подарки",
        "Спорт", "Путешествия", "Образование", "Связь", "Одежда", "Красота", "Дети", "Питомцы",
        "Платежи", "Другое",
      ])
    XCTAssertEqual(
      FinanceCategories.income.map(\.label),
      ["Зарплата", "Подработка", "Подарок", "Проценты", "Возврат", "Продажа", "Другое"])
  }

  func testListsHaveNoDuplicates() {
    for list in [FinanceCategories.expense, FinanceCategories.income] {
      XCTAssertEqual(Set(list.map(\.label)).count, list.count)
      XCTAssertEqual(Set(list.map(\.english)).count, list.count)
    }
  }

  func testEveryCategoryHasADistinctSymbolExceptTheGiftAlias() {
    for list in [FinanceCategories.expense, FinanceCategories.income] {
      let symbols = list.filter { $0.label != "Подарок" }.map(\.symbol)
      XCTAssertEqual(Set(symbols).count, symbols.count)
    }
    let all = (FinanceCategories.expense + FinanceCategories.income).filter {
      $0.label != "Подарок" && $0.label != "Другое"
    }
    XCTAssertEqual(Set(all.map(\.symbol)).count, all.count)
    XCTAssertEqual(FinanceCategories.symbol(for: "Подарок"), FinanceCategories.symbol(for: "Подарки"))
  }

  func testUnknownOrEmptyFallsBackToOther() {
    XCTAssertEqual(FinanceCategories.symbol(for: nil), FinanceCategories.otherSymbol)
    XCTAssertEqual(FinanceCategories.symbol(for: ""), FinanceCategories.otherSymbol)
    XCTAssertEqual(FinanceCategories.symbol(for: "  "), FinanceCategories.otherSymbol)
    XCTAssertEqual(FinanceCategories.symbol(for: "Кофе на вынос"), FinanceCategories.otherSymbol)
    XCTAssertEqual(FinanceCategories.symbol(for: "Другое"), FinanceCategories.otherSymbol)
  }

  func testLookupIgnoresCaseAndSurroundingSpaces() {
    XCTAssertEqual(FinanceCategories.symbol(for: " кафе "), "cup.and.saucer")
    XCTAssertTrue(FinanceCategories.isKnown("Зарплата"))
    XCTAssertFalse(FinanceCategories.isKnown("Кофе"))
    XCTAssertFalse(FinanceCategories.isKnown(nil))
  }

  func testWebsOldCategoriesStillMap() {
    let old = [
      "Зарплата", "Подработка", "Подарок", "Проценты", "Продукты", "Кафе", "Транспорт", "Дом",
      "Здоровье", "Покупки", "Развлечения",
    ]
    for label in old {
      XCTAssertTrue(FinanceCategories.isKnown(label), label)
      XCTAssertNotEqual(FinanceCategories.symbol(for: label), FinanceCategories.otherSymbol, label)
    }
  }

  func testEnglishNames() {
    XCTAssertEqual(FinanceCategories.englishName(for: "Продукты"), "Groceries")
    XCTAssertEqual(FinanceCategories.englishName(for: "Своё"), "Своё")
  }
}
